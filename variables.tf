# ── Projeto ───────────────────────────────────────────────────────────────────

variable "project_name" {
  description = "Nome do projeto — prefixo de todos os recursos AWS"
  type        = string
  default     = "oficina-mecanica"
}

variable "aws_region" {
  description = "Região AWS onde os recursos serão criados"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Ambiente de deployment: dev | staging | prod"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "O valor deve ser dev, staging ou prod."
  }
}

# ── EKS ───────────────────────────────────────────────────────────────────────

variable "cluster_version" {
  description = "Versão do Kubernetes no EKS"
  type        = string
  default     = "1.30"
}

# Fase 4: 3 microsserviços (+ HPA) além do nri-bundle da New Relic. Com o VPC CNI,
# o limite de pods por node vem do número de ENIs/IPs da instância: t3.small = 11
# pods, t3.medium = 17. Só o kube-system + nri-bundle já ocupam ~12 — por isso
# t3.medium e 2 nodes (espaço para rolling update e scale-up do HPA).
variable "node_instance_type" {
  description = "Tipo de instância EC2 para os worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  description = "Quantidade desejada de worker nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Quantidade mínima de worker nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Quantidade máxima de worker nodes (teto do Cluster Autoscaler)"
  type        = number
  default     = 3
}

# ── Observabilidade (New Relic) ─────────────────────────────────────────────────

variable "newrelic_account_id" {
  description = "Account ID da New Relic"
  type        = number
}

variable "newrelic_api_key" {
  description = "User API Key da New Relic (NRAK-...), usada pelo provider Terraform para criar policies/dashboards"
  type        = string
  sensitive   = true
}

variable "newrelic_region" {
  description = "Região da conta New Relic: US ou EU"
  type        = string
  default     = "US"
}

variable "newrelic_license_key" {
  description = "License key da New Relic (INGEST-LICENSE), usada pelo agente de monitoramento do Kubernetes"
  type        = string
  sensitive   = true
}

variable "newrelic_app_names" {
  description = "Nomes das aplicações no New Relic APM (um por microsserviço da Fase 4) — devem bater com NEW_RELIC_APP_NAME do ConfigMap de cada serviço"
  type        = list(string)
  default     = ["oficina-os-service", "oficina-billing-service", "oficina-exec-prod-service"]
}

variable "newrelic_k8s_chart_version" {
  description = "Versão do chart Helm newrelic/nri-bundle (monitoramento de CPU/memória do cluster)"
  type        = string
  default     = "5.0.94"
}

variable "newrelic_notification_email" {
  description = "E-mail que recebe os alertas de falha no processamento de ordens de serviço"
  type        = string
}
