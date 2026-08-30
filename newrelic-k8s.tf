# Monitoramento de CPU/memória do cluster (nós e pods) e healthchecks de
# workloads, via o bundle oficial da New Relic para Kubernetes.
resource "kubernetes_namespace" "newrelic" {
  metadata {
    name = "newrelic"
  }

  depends_on = [module.eks]
}

resource "helm_release" "newrelic_bundle" {
  name       = "newrelic-bundle"
  namespace  = kubernetes_namespace.newrelic.metadata[0].name
  repository = "https://helm-charts.newrelic.com"
  chart      = "nri-bundle"
  version    = var.newrelic_k8s_chart_version

  # Padrão (300s) é curto para esse chart: sobe vários componentes, incluindo um
  # DaemonSet por node — com pull de imagem "frio" em cluster recém-criado, passa
  # fácil de 5min. Se ainda assim estourar, os pods costumam já estar saudáveis
  # (só o "wait" do Helm demorou) — rodar o apply de novo resolve.
  timeout = 600

  values = [
    yamlencode({
      global = {
        licenseKey = var.newrelic_license_key
        cluster    = module.eks.cluster_name
      }
      newrelic-infrastructure = {
        privileged = true
      }
      "kube-state-metrics" = {
        enabled = true
      }
      prometheus = {
        enabled = true
      }
      # Logs da aplicação já vão para a New Relic via application_logging.forwarding
      # do agente APM (repositório soat-fiap-oficina-mecanica) — evita duplicar.
      logging = {
        enabled = false
      }
    })
  ]

  depends_on = [kubernetes_namespace.newrelic]
}
