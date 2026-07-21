resource "argocd_application" "root" {
  depends_on = [
    helm_release.argocd,
    kubernetes_namespace.database,
    kubernetes_namespace.apps,
    kubernetes_secret.mysql_database,
    kubernetes_secret.mysql_apps,
  ]

  metadata {
    name      = "root"
    namespace = var.argocd_namespace
  }

  spec {
    project = "default"

    source {
      repo_url        = var.repo_url
      target_revision = var.target_revision
      path            = var.argocd_apps_path

      helm {
        parameter {
          name  = "repoUrl"
          value = var.repo_url
        }
        parameter {
          name  = "targetRevision"
          value = var.target_revision
        }
        parameter {
          name  = "dbNamespace"
          value = var.db_namespace
        }
        parameter {
          name  = "appNamespace"
          value = var.app_namespace
        }
      }
    }

    destination {
      server    = "https://kubernetes.default.svc"
      namespace = var.argocd_namespace
    }

    sync_policy {
      automated {
        prune     = true
        self_heal = true
      }
    }
  }
}
