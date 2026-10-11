# Lets GitHub Actions assume an AWS role with short-lived OIDC tokens,
# so no long-lived AWS keys are stored in GitHub secrets.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

variable "name" {
  description = "Name of the IAM role GitHub Actions will assume."
  type        = string
}

variable "github_repo" {
  description = "owner/repo allowed to assume the role."
  type        = string
}

variable "allowed_refs" {
  description = "Git refs allowed to assume the role (e.g. refs/heads/main)."
  type        = list(string)
  default     = ["refs/heads/main"]
}

variable "policy_arns" {
  description = "Managed policy ARNs to attach to the role."
  type        = list(string)
  default     = []
}

variable "inline_policy_json" {
  description = "Optional inline policy document."
  type        = string
  default     = null
}

variable "create_provider" {
  description = "Create the GitHub OIDC provider (only one per AWS account)."
  type        = bool
  default     = true
}

data "aws_iam_openid_connect_provider" "existing" {
  count = var.create_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  count           = var.create_provider ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

locals {
  provider_arn = var.create_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.existing[0].arn
  subjects     = concat([for r in var.allowed_refs : "repo:${var.github_repo}:ref:${r}"], ["repo:${var.github_repo}:pull_request"])
}

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.subjects
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = var.name
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each   = toset(var.policy_arns)
  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "inline" {
  count  = var.inline_policy_json == null ? 0 : 1
  name   = "${var.name}-inline"
  role   = aws_iam_role.this.id
  policy = var.inline_policy_json
}

output "role_arn" {
  value = aws_iam_role.this.arn
}
