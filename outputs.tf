# ── VPC ───────────────────────────────────────────────────────────────────────

output "vpc_id" {
  description = "ID da VPC criada"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas (EKS nodes + RDS). Consumido pelo repositório infra-data via terraform_remote_state."
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs das subnets públicas (load balancers)"
  value       = module.vpc.public_subnet_ids
}

# ── EKS ───────────────────────────────────────────────────────────────────────

output "cluster_name" {
  description = "Nome do cluster EKS"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint da API do cluster EKS"
  value       = module.eks.cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "Certificado CA do cluster (base64)"
  value       = module.eks.cluster_ca_certificate
  sensitive   = true
}

output "node_security_group_id" {
  description = "Security group dos worker nodes. Consumido pelo repositório infra-data via terraform_remote_state."
  value       = module.eks.node_security_group_id
}

output "cluster_security_group_id" {
  description = "Security group gerenciado pelo EKS. Consumido pelo repositório infra-data via terraform_remote_state."
  value       = module.eks.cluster_security_group_id
}

output "kubeconfig_command" {
  description = "Comando para configurar kubectl apontando para este cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

# ── Observabilidade (New Relic) ─────────────────────────────────────────────────

output "newrelic_dashboard_url" {
  description = "Link do dashboard (volume de OS, tempo médio por status, erros, latência)"
  value       = newrelic_one_dashboard.oficina.permalink
}
