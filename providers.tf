terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    newrelic = {
      source  = "newrelic/newrelic"
      version = "~> 3.43"
    }
  }

  # Valores injetados via -backend-config no CI/CD (mesmo padrão do antigo infra/ do
  # repositório da aplicação): bucket = TF_STATE_BUCKET, key = "oficina-mecanica/infra-kube/terraform.tfstate"
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Autenticação do cluster recém-criado por module.eks (sem depender de kubeconfig local).
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

# NOTA: como o provider kubernetes/helm depende de outputs de module.eks, o `terraform apply`
# inicial (cluster ainda não existe) pode falhar ao tentar configurar esses providers.
# Nesse caso, faça o bootstrap em duas etapas:
#   terraform apply -target=module.vpc -target=module.eks
#   terraform apply
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "newrelic" {
  account_id = var.newrelic_account_id
  api_key    = var.newrelic_api_key
  region     = var.newrelic_region
}
