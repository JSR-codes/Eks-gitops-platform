variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
  default     = "gitops-dev"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane."
  type        = string
  default     = "1.31"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "node_instance_types" {
  description = "Instance types for the managed node group. Spot keeps the demo cheap."
  type        = list(string)
  default     = ["t3.large", "t3a.large"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT."
  type        = string
  default     = "SPOT"
}

variable "node_min" {
  type    = number
  default = 2
}

variable "node_max" {
  type    = number
  default = 4
}

variable "node_desired" {
  type    = number
  default = 2
}

variable "github_repo" {
  description = "owner/repo that GitHub Actions runs from."
  type        = string
  default     = "JSR-codes/eks-gitops-platform"
}

variable "gitops_repo_url" {
  description = "Git URL Argo CD watches."
  type        = string
  default     = "https://github.com/JSR-codes/eks-gitops-platform.git"
}

variable "gitops_revision" {
  description = "Branch Argo CD tracks."
  type        = string
  default     = "main"
}

variable "admin_principal_arns" {
  description = "IAM role/user ARNs that get cluster-admin through EKS access entries."
  type        = list(string)
  default     = []
}

variable "create_github_oidc_provider" {
  description = "Set false if the account already has the GitHub OIDC provider."
  type        = bool
  default     = true
}
