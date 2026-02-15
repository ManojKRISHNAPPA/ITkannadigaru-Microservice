locals {
  vpc_id             = data.terraform_remote_state.network.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids
  public_subnet_ids  = data.terraform_remote_state.network.outputs.public_subnet_ids
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.project
  cluster_version = var.kubernetes_version

  vpc_id     = local.vpc_id
  subnet_ids = local.private_subnet_ids

  # Enable IAM Roles for Service Accounts (IRSA) - required for ALB controller later
  enable_irsa = true

  # Endpoint access
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true
  enable_cluster_creator_admin_permissions = true


  # Managed Node Group(s)
  eks_managed_node_groups = {
    default = {
      name           = "${var.project}-ng"
      instance_types = ["c7i-flex.large"]
      min_size       = 1
      max_size       = 3
      desired_size   = 2

      subnet_ids = local.private_subnet_ids
    }
  }

  tags = {
    Project = var.project
  }
}
