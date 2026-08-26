# O chart Helm oficial do Konga está sem manutenção há anos, então ele é provisionado
# diretamente com o provider kubernetes (Deployment + Service + PVC), e não via Helm.

resource "random_password" "konga_token_secret" {
  length  = 32
  special = false
}

resource "kubernetes_secret" "konga" {
  metadata {
    name      = "konga-secret"
    namespace = kubernetes_namespace.kong.metadata[0].name
  }

  data = {
    TOKEN_SECRET = random_password.konga_token_secret.result
  }
}

resource "kubernetes_persistent_volume_claim" "konga" {
  metadata {
    name      = "konga-data"
    namespace = kubernetes_namespace.kong.metadata[0].name
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = var.konga_storage_size
      }
    }
  }

  # StorageClass é WaitForFirstConsumer; só binda quando o Deployment (que depende desta PVC) a referencia.
  wait_until_bound = false
}

resource "kubernetes_deployment" "konga" {
  metadata {
    name      = "konga"
    namespace = kubernetes_namespace.kong.metadata[0].name
    labels = {
      app = "konga"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "konga"
      }
    }

    template {
      metadata {
        labels = {
          app = "konga"
        }
      }

      spec {
        container {
          name  = "konga"
          image = "pantsel/konga:${var.konga_image_tag}"

          port {
            container_port = 1337
          }

          # NODE_ENV=production desativaria a conexão "sqlite" (definida só no ambiente
          # development do Sails.js), incompatível com o DB_ADAPTER=sqlite abaixo.
          env {
            name  = "NODE_ENV"
            value = "development"
          }

          # Estado da UI (usuários, snapshots) fica em SQLite local, persistido via PVC.
          env {
            name  = "DB_ADAPTER"
            value = "sqlite"
          }

          env {
            name  = "DB_DATABASE"
            value = "/app/kongadata/konga.db"
          }

          env {
            name = "TOKEN_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.konga.metadata[0].name
                key  = "TOKEN_SECRET"
              }
            }
          }

          volume_mount {
            name       = "konga-data"
            mount_path = "/app/kongadata"
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 1337
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }
        }

        volume {
          name = "konga-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.konga.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [helm_release.kong]
}

resource "kubernetes_service" "konga" {
  metadata {
    name      = "konga"
    namespace = kubernetes_namespace.kong.metadata[0].name
  }

  spec {
    selector = {
      app = "konga"
    }

    port {
      port        = 1337
      target_port = 1337
    }

    type = "ClusterIP"
  }
}
