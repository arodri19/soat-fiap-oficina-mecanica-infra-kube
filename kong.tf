resource "kubernetes_namespace" "kong" {
  metadata {
    name = var.kong_namespace
  }

  depends_on = [module.eks]
}

# Postgres dedicado ao Kong (não é o banco da aplicação, que vive no repositório infra-data).
resource "random_password" "kong_postgres" {
  length  = 24
  special = false
}

resource "helm_release" "kong" {
  name       = "kong"
  namespace  = kubernetes_namespace.kong.metadata[0].name
  repository = "https://charts.konghq.com"
  chart      = "kong"
  version    = var.kong_chart_version

  values = [
    yamlencode({
      # Nome fixo para os Services (kong-proxy / kong-admin), independente do nome do release.
      fullnameOverride = "kong"

      env = {
        database = "postgres"
      }

      # Chart provisiona um Postgres (bitnami) dedicado como dependência quando habilitado.
      postgresql = {
        enabled = true
        auth = {
          username = "kong"
          password = random_password.kong_postgres.result
          database = "kong"
        }
        primary = {
          persistence = {
            size = var.kong_postgres_storage_size
          }
        }
      }

      proxy = {
        type = var.kong_proxy_service_type
      }

      # Admin API nunca deve ser exposta fora do cluster: só ClusterIP, consumida pelo Konga.
      admin = {
        enabled = true
        type    = "ClusterIP"
      }

      ingressController = {
        enabled = false
      }
    })
  ]

  depends_on = [kubernetes_namespace.kong]
}
