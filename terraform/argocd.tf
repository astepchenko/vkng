resource "random_password" "argocd_admin" {
  length  = 24
  special = false
}

# Install Argo CD via the official Helm chart.
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = var.argocd_namespace
  create_namespace = true

  # Serve the API/UI over plain HTTP (local demo only) and expose it via
  # Ingress at http://${var.argocd_hostname} - no port-forward required.
  values = [
    yamlencode({
      configs = {
        params = {
          "server.insecure" = true
        }
        secret = {
          argocdServerAdminPassword = bcrypt(random_password.argocd_admin.result)
          # Fixed, not timestamp() - a changing mtime invalidates every session on each apply.
          argocdServerAdminPasswordMtime = "2024-01-01T00:00:00Z"
        }
      }
      server = {
        ingress = {
          enabled          = true
          ingressClassName = "traefik"
          hostname         = var.argocd_hostname
          tls              = false
        }
      }
    })
  ]

  # Give the CRDs and controllers time to become ready before Applications
  # are created.
  wait    = true
  timeout = 600
}
