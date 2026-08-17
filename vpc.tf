# ── Módulo VPC ────────────────────────────────────────────────────────────────
# Cria a rede completa: VPC, subnets públicas/privadas,
# Internet Gateway, NAT Gateway e route tables.
module "vpc" {
  source = "./modules/vpc"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region
}
