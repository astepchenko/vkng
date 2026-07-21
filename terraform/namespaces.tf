# Terraform owns the application namespaces and the MySQL credentials, so the
# password is generated at apply time and never committed to Git. Argo CD then
# syncs workloads into these namespaces (CreateNamespace=false).

resource "kubernetes_namespace" "database" {
  metadata {
    name = var.db_namespace
  }
}

resource "kubernetes_namespace" "apps" {
  metadata {
    name = var.app_namespace
  }
}

resource "random_password" "mysql_root" {
  length = 24
  # Avoid special characters to keep DSN/connection strings simple.
  special = false
}

resource "random_password" "mysql_user" {
  length  = 24
  special = false
}

# Consumed by the Bitnami MySQL chart (auth.existingSecret) and by the backup
# CronJob (root password).
resource "kubernetes_secret" "mysql_database" {
  metadata {
    name      = var.mysql_secret_name
    namespace = kubernetes_namespace.database.metadata[0].name
  }
  type = "Opaque"
  data = {
    "mysql-root-password" = random_password.mysql_root.result
    "mysql-password"      = random_password.mysql_user.result
  }
}

# Consumed by the backend (application user password only).
resource "kubernetes_secret" "mysql_apps" {
  metadata {
    name      = var.mysql_secret_name
    namespace = kubernetes_namespace.apps.metadata[0].name
  }
  type = "Opaque"
  data = {
    "mysql-password" = random_password.mysql_user.result
  }
}
