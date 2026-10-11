# Pin the exact AZs so the subnet layout never shifts if AWS adds a zone
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "zone-name"
    values = [for s in var.az_suffixes : "${var.region}${s}"]
  }
}

locals {
  azs = data.aws_availability_zones.available.names

  tags = {
    Project     = "eks-gitops-platform"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

################################################################################
# Networking: 3 AZs, private subnets for nodes, public for load balancers
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, 48 + i)]

  enable_nat_gateway   = true
  single_nat_gateway   = true # one NAT keeps dev costs down; use one per AZ in prod
  enable_dns_hostnames = true

  enable_flow_log                                 = true
  create_flow_log_cloudwatch_log_group            = true
  create_flow_log_cloudwatch_iam_role             = true
  flow_log_cloudwatch_log_group_retention_in_days = 14

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

################################################################################
# EKS cluster with a managed node group and access entries
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  cluster_endpoint_public_access = true
  enable_irsa                    = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_enabled_log_types = ["api", "audit", "authenticator"]

  cluster_addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = {}
    eks-pod-identity-agent = {}
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
  }

  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types
      capacity_type  = var.node_capacity_type
      min_size       = var.node_min
      max_size       = var.node_max
      desired_size   = var.node_desired

      labels = {
        workload = "general"
      }
    }
  }

  enable_cluster_creator_admin_permissions = true

  access_entries = {
    for idx, arn in var.admin_principal_arns : "admin-${idx}" => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }
}

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.44"

  role_name             = "${var.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

################################################################################
# Container registry for the demo app
################################################################################

resource "aws_ecr_repository" "app" {
  name                 = "demo-app"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 30 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 30
      }
      action = { type = "expire" }
    }]
  })
}

################################################################################
# GitHub Actions -> AWS via OIDC (no static keys)
################################################################################

data "aws_iam_policy_document" "ci_push" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.app.arn]
  }
}

module "github_ci_role" {
  source = "../../modules/github-oidc"

  name               = "${var.cluster_name}-github-ci"
  github_repo        = var.github_repo
  create_provider    = var.create_github_oidc_provider
  inline_policy_json = data.aws_iam_policy_document.ci_push.json
}

################################################################################
# Argo CD: installed once by Terraform, then it manages everything else
################################################################################

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.6.12"
  values           = [file("${path.module}/argocd-values.yaml")]

  depends_on = [module.eks]
}

# The root "app of apps". Everything under gitops/apps is synced from Git.
resource "helm_release" "argocd_root_app" {
  name      = "root-app"
  namespace = "argocd"
  chart     = "${path.module}/../../../gitops/bootstrap"

  set {
    name  = "repoURL"
    value = var.gitops_repo_url
  }
  set {
    name  = "targetRevision"
    value = var.gitops_revision
  }

  depends_on = [helm_release.argocd]
}
