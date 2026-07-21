provider "kubernetes" {
  config_path    = pathexpand(var.kubeconfig)
  config_context = var.kube_context
}

provider "helm" {
  kubernetes {
    config_path    = pathexpand(var.kubeconfig)
    config_context = var.kube_context
  }
}

provider "random" {}

provider "argocd" {
  username                    = "admin"
  password                    = random_password.argocd_admin.result
  port_forward_with_namespace = var.argocd_namespace
  plain_text                  = true # server.insecure=true in argocd.tf - no TLS to negotiate

  kubernetes {
    config_context = var.kube_context # no config_path here - reads $KUBECONFIG / default path
  }
}
