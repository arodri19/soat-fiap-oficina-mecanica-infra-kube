# Rotas JWT do Kong são opt-in (var.enable_kong_jwt_routes) porque dependem do output
# function_url do repositório serverless — que só existe depois que ele é implantado, e
# o serverless por sua vez depende deste repositório (VPC/EKS). Isso quebraria o "bootstrap"
# (a 1ª aplicação nunca teria o remote state do serverless para ler) se fosse incondicional.
#
# Ordem de implantação:
#   1. infra-kube    (enable_kong_jwt_routes = false, o padrão) — cria VPC/EKS/Kong/Konga
#   2. infra-data    — RDS
#   3. serverless    — Lambda (usa outputs do infra-kube e do infra-data)
#   4. infra-kube de novo, agora com enable_kong_jwt_routes = true — liga as rotas JWT

data "terraform_remote_state" "serverless" {
  count = var.enable_kong_jwt_routes ? 1 : 0

  backend = "s3"

  config = {
    bucket = var.tf_state_bucket
    key    = "oficina-mecanica/serverless/terraform.tfstate"
    region = var.aws_region
  }
}

locals {
  lambda_function_url = var.enable_kong_jwt_routes ? data.terraform_remote_state.serverless[0].outputs.function_url : null
  # "iss" que a Lambda grava no JWT (src/handler.js) — é assim que o plugin jwt do Kong
  # descobre qual consumer/credencial usar para validar a assinatura do token.
  kong_jwt_consumer_key = "oficina-mecanica-app"
}

resource "kubernetes_secret" "kong_jwt" {
  count = var.enable_kong_jwt_routes ? 1 : 0

  metadata {
    name      = "kong-jwt-secret"
    namespace = kubernetes_namespace.kong.metadata[0].name
  }

  data = {
    JWT_SECRET = var.jwt_secret
  }
}

# Admin API do Kong é ClusterIP (não exposta fora do cluster, de propósito), então a
# configuração de Services/Routes/Consumer/plugin roda de dentro do cluster via Job.
resource "kubernetes_job" "kong_routes" {
  count = var.enable_kong_jwt_routes ? 1 : 0

  metadata {
    name      = "kong-routes-config"
    namespace = kubernetes_namespace.kong.metadata[0].name
  }

  spec {
    backoff_limit = 2

    template {
      metadata {
        labels = { app = "kong-routes-config" }
      }

      spec {
        restart_policy = "Never"

        container {
          name  = "configure-kong"
          image = "curlimages/curl:8.10.1"

          env {
            name  = "LAMBDA_URL"
            value = local.lambda_function_url
          }
          env {
            name  = "CONSUMER_KEY"
            value = local.kong_jwt_consumer_key
          }
          env {
            name = "JWT_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.kong_jwt[0].metadata[0].name
                key  = "JWT_SECRET"
              }
            }
          }

          command = ["sh", "-c", <<-EOT
            set -e
            # Service kong-admin só expõe a porta TLS (8444); admin.http vem desabilitado
            # por padrão nas versões recentes do chart. Certificado é autoassinado (-k).
            ADMIN="https://kong-admin.kong.svc.cluster.local:8444"
            # --http1.1: a Admin API (Lapis) não suporta HTTP/2, que o curl negocia via ALPN por padrão em TLS.
            CURL="curl -sk --http1.1 --max-time 10"

            echo "aguardando admin api..."
            for i in $(seq 1 30); do
              $CURL "$ADMIN/status" > /dev/null 2>&1 && break
              sleep 2
            done

            echo "configurando rota publica (login)..."
            $CURL -f -X PUT "$ADMIN/services/auth-cpf" -d "url=$LAMBDA_URL"
            $CURL -f -X PUT "$ADMIN/services/auth-cpf/routes/auth-cpf-route" -d "paths[]=/auth/cpf" -d "strip_path=true"

            echo "configurando rota protegida (jwt)..."
            $CURL -f -X PUT "$ADMIN/services/protected-demo" -d "url=$LAMBDA_URL"
            $CURL -f -X PUT "$ADMIN/services/protected-demo/routes/protected-demo-route" -d "paths[]=/me" -d "strip_path=true"
            $CURL -f -X POST "$ADMIN/routes/protected-demo-route/plugins" -d "name=jwt" || true

            echo "configurando consumer + credencial jwt..."
            $CURL -f -X PUT "$ADMIN/consumers/$CONSUMER_KEY"
            $CURL -X DELETE "$ADMIN/consumers/$CONSUMER_KEY/jwt/$CONSUMER_KEY" || true
            $CURL -f -X POST "$ADMIN/consumers/$CONSUMER_KEY/jwt" -d "key=$CONSUMER_KEY" -d "algorithm=HS256" -d "secret=$JWT_SECRET"

            echo "kong routes configured"
          EOT
          ]
        }
      }
    }
  }

  wait_for_completion = true

  timeouts {
    create = "3m"
  }

  depends_on = [helm_release.kong, kubernetes_secret.kong_jwt]
}
