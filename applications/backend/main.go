// Command backend is an HTTP API that records "visits" in MySQL.
//
// It exposes:
//
//	GET  /healthz          liveness  - always 200 once the process is up
//	GET  /readyz           readiness - 200 only when the database is reachable
//	GET  /api/visits/count returns the total visit count without inserting
//	POST /api/visits       inserts one row and returns the total visit count
//
// All configuration comes from environment variables; the database password
// is injected from a Kubernetes Secret via envFrom/secretKeyRef.
package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	_ "github.com/go-sql-driver/mysql"
)

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func mustDB() *sql.DB {
	dsn := fmt.Sprintf("%s:%s@tcp(%s:%s)/%s?parseTime=true&timeout=5s",
		env("DB_USER", "appuser"),
		os.Getenv("DB_PASSWORD"),
		env("DB_HOST", "mysql.database.svc.cluster.local"),
		env("DB_PORT", "3306"),
		env("DB_NAME", "appdb"),
	)

	db, err := sql.Open("mysql", dsn)
	if err != nil {
		log.Fatalf("open db: %v", err)
	}
	db.SetConnMaxLifetime(2 * time.Minute)
	db.SetMaxOpenConns(10)

	// Wait for the database to become reachable (MySQL may still be starting).
	for i := 1; i <= 30; i++ {
		if err = db.Ping(); err == nil {
			break
		}
		log.Printf("waiting for db (%d/30): %v", i, err)
		time.Sleep(2 * time.Second)
	}
	if err != nil {
		log.Fatalf("db unreachable after retries: %v", err)
	}

	// Ensure the schema exists (idempotent - this is the only place it's created).
	const ddl = `CREATE TABLE IF NOT EXISTS visits (
		id        BIGINT AUTO_INCREMENT PRIMARY KEY,
		created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
	)`
	if _, err := db.Exec(ddl); err != nil {
		log.Fatalf("ensure schema: %v", err)
	}
	return db
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func main() {
	db := mustDB()
	defer db.Close()

	hostname, _ := os.Hostname()

	http.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	http.HandleFunc("/readyz", func(w http.ResponseWriter, _ *http.Request) {
		if err := db.Ping(); err != nil {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "db unreachable"})
			return
		}
		writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
	})

	countVisits := func(w http.ResponseWriter) {
		var count int64
		if err := db.QueryRow("SELECT COUNT(*) FROM visits").Scan(&count); err != nil {
			log.Printf("count visits: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "count failed"})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"count": count, "servedBy": hostname})
	}

	http.HandleFunc("GET /api/visits/count", func(w http.ResponseWriter, _ *http.Request) {
		countVisits(w)
	})

	http.HandleFunc("POST /api/visits", func(w http.ResponseWriter, _ *http.Request) {
		if _, err := db.Exec("INSERT INTO visits () VALUES ()"); err != nil {
			log.Printf("insert visit: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "insert failed"})
			return
		}
		countVisits(w)
	})

	addr := ":" + env("PORT", "8080")
	log.Printf("backend listening on %s", addr)
	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatal(err)
	}
}
