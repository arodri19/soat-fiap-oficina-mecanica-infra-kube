# ── Módulo EKS ────────────────────────────────────────────────────────────────
# Cria o cluster Kubernetes gerenciado (control plane + node group)
# com roles IAM, security groups e configuração de rede.
module "eks" {
  source = "./modules/eks"

  project_name       = var.project_name
  environment        = var.environment
  cluster_version    = var.cluster_version
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  node_instance_type = var.node_instance_type
  node_desired_size  = var.node_desired_size
  node_min_size      = var.node_min_size
  node_max_size      = var.node_max_size
}
