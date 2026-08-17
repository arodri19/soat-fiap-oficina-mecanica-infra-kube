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

variable "node_instance_type" {
  description = "Tipo de instância EC2 para os worker nodes"
  type        = string
  default     = "t3.small"
}

variable "node_desired_size" {
  description = "Quantidade desejada de worker nodes"
  type        = number
  default     = 1
}

variable "node_min_size" {
  description = "Quantidade mínima de worker nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Quantidade máxima de worker nodes (teto do Cluster Autoscaler)"
  type        = number
  default     = 1
}

# ── API Gateway (Kong + Konga) ─────────────────────────────────────────────────

variable "kong_namespace" {
  description = "Namespace onde o Kong e o Konga serão instalados."
  type        = string
  default     = "kong"
}

variable "kong_chart_version" {
  description = "Versão do chart Helm oficial do Kong (repositório https://charts.konghq.com)."
  type        = string
  default     = "2.44.0"
}

variable "kong_proxy_service_type" {
  description = "Tipo do Service Kubernetes exposto pelo Kong Proxy (porta de entrada do tráfego da API)."
  type        = string
  default     = "LoadBalancer"

  validation {
    condition     = contains(["ClusterIP", "NodePort", "LoadBalancer"], var.kong_proxy_service_type)
    error_message = "kong_proxy_service_type deve ser ClusterIP, NodePort ou LoadBalancer."
  }
}

variable "kong_postgres_storage_size" {
  description = "Tamanho do volume persistente do Postgres dedicado ao Kong (armazena rotas, services e plugins)."
  type        = string
  default     = "2Gi"
}

variable "konga_image_tag" {
  description = "Tag da imagem Docker do Konga (UI de administração do Kong)."
  type        = string
  default     = "0.14.9"
}

variable "konga_storage_size" {
  description = "Tamanho do volume persistente usado pelo Konga para guardar seu próprio estado (usuários, snapshots)."
  type        = string
  default     = "1Gi"
}
