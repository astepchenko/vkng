terraform {
  required_version = ">= 1.5.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "2.17.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.38.0"
    }
    argocd = {
      source  = "argoproj-labs/argocd"
      version = "7.15.3"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.0"
    }
  }
}
