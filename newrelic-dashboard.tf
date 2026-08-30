# Dashboard com os três painéis exigidos pela Fase 3. "Volume diário" e "tempo
# médio de execução por status" vêm de eventos customizados emitidos pela
# aplicação (OrderCreated / OrderStatusChanged — ver
# src/infrastructure/monitoring/newrelicEvents.js no repositório
# soat-fiap-oficina-mecanica) via o agente APM.
resource "newrelic_one_dashboard" "oficina" {
  name = "${var.project_name}-${var.environment} — Oficina Mecanica"

  page {
    name = "Ordens de Servico"

    widget_billboard {
      title  = "Volume diario de ordens de servico"
      row    = 1
      column = 1
      width  = 4
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT count(*) FROM OrderCreated SINCE 1 day ago"
      }
    }

    # NRQL não tem operador de módulo — não dá pra montar "1h 15m 30s" a partir de
    # um average() dentro da própria query (testado: "%" dá erro de sintaxe). E o
    # data_format (type=duration) do widget exige adivinhar o nome exato da coluna
    # gerada pela query, o que não dá pra validar sem abrir o dashboard — na prática
    # não funcionou. Por isso a MÉDIA REAL é calculada e formatada fora do NRQL:
    # POST /api/metrics/status-duration-averages/recompute (repositório
    # soat-fiap-oficina-mecanica) consulta a própria New Relic (average() sobre o
    # histórico), formata como "1h 15m", e republica um evento por status
    # (OrderStatusAverageDuration) — aqui só exibimos o snapshot mais recente disso.
    widget_table {
      title  = "Tempo medio de execucao por status"
      row    = 1
      column = 5
      width  = 8
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT latest(averageSeconds) AS 'Media (segundos)', latest(averageLabel) AS 'Media formatada' FROM OrderStatusAverageDuration FACET fromStatus SINCE 1 day ago"
      }
    }

    widget_line {
      title  = "Volume de OS criadas (serie temporal)"
      row    = 4
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT count(*) FROM OrderCreated TIMESERIES SINCE 1 week ago"
      }
    }

    widget_line {
      title  = "Erros e falhas nas integracoes"
      row    = 4
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT count(*) FROM TransactionError WHERE appName = '${var.newrelic_app_name}' TIMESERIES SINCE 1 week ago"
      }
    }

    widget_billboard {
      title  = "Latencia media das APIs (ms)"
      row    = 7
      column = 1
      width  = 4
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT average(duration) * 1000 FROM Transaction WHERE appName = '${var.newrelic_app_name}' SINCE 30 minutes ago"
      }
    }

    # "Healthcheck e uptime" reais vêm das httpGet readiness/liveness probes do
    # Kubernetes (GET /health, ver k8s/app-deployment.yaml no repositório da
    # aplicação) — aqui, o proxy é a taxa de requisições bem-sucedidas via APM.
    widget_billboard {
      title  = "Taxa de requisicoes bem-sucedidas (uptime aproximado)"
      row    = 7
      column = 5
      width  = 4
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        # response.status não existe no agente Node.js — o atributo real é
        # http.statusCode (confirmado via SELECT keyset() FROM Transaction).
        # Com o nome errado, a condição do WHERE nunca batia e o painel sempre
        # mostrava 0%, mesmo com 100% das requisições < 500.
        query = "SELECT percentage(count(*), WHERE numeric(http.statusCode) < 500) FROM Transaction WHERE appName = '${var.newrelic_app_name}' SINCE 1 day ago"
      }
    }
  }
}
