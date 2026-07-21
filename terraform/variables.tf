variable "kubeconfig" {
  description = "Path to the kubeconfig file."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "kubeconfig context of the k3d cluster."
  type        = string
  default     = "k3d-vkng"
}

variable "repo_url" {
  description = "Git repository URL that Argo CD tracks."
  type        = string
  default     = "https://github.com/astepchenko/vkng.git"
}

variable "target_revision" {
  description = "Git revision (branch, tag or SHA) that Argo CD syncs from."
  type        = string
  default     = "main"
}

variable "argocd_namespace" {
  description = "Namespace for the Argo CD installation."
  type        = string
  default     = "argocd"
}

variable "argocd_chart_version" {
  description = "Version of the argo-cd Helm chart."
  type        = string
  default     = "10.1.4"
}

variable "argocd_hostname" {
  description = "Hostname the Argo CD UI Ingress is exposed on."
  type        = string
  default     = "argocd.localhost"
}

variable "db_namespace" {
  description = "Namespace for the MySQL database and backups."
  type        = string
  default     = "database"
}

variable "app_namespace" {
  description = "Namespace for the frontend/backend applications."
  type        = string
  default     = "apps"
}

variable "mysql_secret_name" {
  description = "Name of the Secret holding MySQL credentials."
  type        = string
  default     = "mysql-credentials"
}

variable "argocd_apps_path" {
  description = "Path in the Git repository holding the App-of-Apps child Application manifests."
  type        = string
  default     = "argocd-apps"
}
