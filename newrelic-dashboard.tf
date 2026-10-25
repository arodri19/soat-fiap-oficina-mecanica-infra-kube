# Dashboard com os três painéis exigidos pela Fase 3. "Volume diário" e "tempo
# médio de execução por status" vêm de eventos customizados emitidos pela
# aplicação (OrderCreated / OrderStatusChanged — ver
# src/infrastructure/monitoring/newrelicEvents.js no repositório
# soat-fiap-oficina-mecanica) via o agente APM.
locals {
  # "'oficina-os-service', 'oficina-billing-service', ..." — usado em cláusulas NRQL IN (...)
  nr_app_names = join(", ", [for name in var.newrelic_app_names : "'${name}'"])
}

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
        query      = "SELECT count(*) FROM TransactionError WHERE appName IN (${local.nr_app_names}) FACET appName TIMESERIES SINCE 1 week ago"
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
        query      = "SELECT average(duration) * 1000 FROM Transaction WHERE appName IN (${local.nr_app_names}) AND transactionType = 'Web' SINCE 30 minutes ago"
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
        query = "SELECT percentage(count(*), WHERE numeric(http.statusCode) < 500) FROM Transaction WHERE appName IN (${local.nr_app_names}) AND transactionType = 'Web' SINCE 1 day ago"
      }
    }
  }

  # ── Fase 4: saga orquestrada e microsserviços ────────────────────────────────
  # Eventos customizados emitidos pelos três serviços (newrelicEvents.js de cada
  # repositório) + Distributed Tracing: o trace de uma OS atravessa HTTP → SQS →
  # billing/exec-prod → SQS → os-service (headers propagados no envelope).
  page {
    name = "Saga e Microsservicos"

    widget_billboard {
      title  = "Sagas por desfecho (24h)"
      row    = 1
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT filter(count(*), WHERE eventType() = 'SagaStarted') AS 'Iniciadas', filter(count(*), WHERE eventType() = 'SagaCompleted') AS 'Concluidas', filter(count(*), WHERE eventType() = 'SagaCompensated') AS 'Compensadas', filter(count(*), WHERE eventType() = 'SagaFailed') AS 'Falhas (manual)' FROM SagaStarted, SagaCompleted, SagaCompensated, SagaFailed SINCE 1 day ago"
      }
    }

    widget_pie {
      title  = "Motivos de compensacao"
      row    = 1
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT count(*) FROM SagaCompensationStarted FACET reason SINCE 1 week ago LIMIT 10"
      }
    }

    widget_line {
      title  = "Etapas da saga concluidas"
      row    = 4
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT count(*) FROM SagaStepCompleted FACET step TIMESERIES SINCE 1 day ago"
      }
    }

    widget_line {
      title  = "Pagamentos Mercado Pago por status"
      row    = 4
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT count(*) FROM PaymentStatusChanged FACET status TIMESERIES SINCE 1 day ago"
      }
    }

    widget_line {
      title  = "Fila de execucao (eventos por status)"
      row    = 7
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT count(*) FROM ExecutionStatusChanged FACET status TIMESERIES SINCE 1 day ago"
      }
    }

    widget_table {
      title  = "Mensagens SQS processadas por servico"
      row    = 7
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT count(*), average(duration) * 1000 AS 'ms' FROM Transaction WHERE appName IN (${local.nr_app_names}) AND transactionType = 'Other' FACET appName, name SINCE 1 day ago LIMIT 30"
      }
    }

    widget_line {
      title  = "Throughput HTTP por microsservico"
      row    = 10
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT rate(count(*), 1 minute) FROM Transaction WHERE appName IN (${local.nr_app_names}) AND transactionType = 'Web' FACET appName TIMESERIES SINCE 3 hours ago"
      }
    }

    widget_table {
      title  = "Traces distribuidos recentes (OS atravessando servicos)"
      row    = 10
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT uniqueCount(entity.name) AS 'servicos', count(*) AS 'spans', max(duration.ms) AS 'duracao max (ms)' FROM Span WHERE entity.name IN (${local.nr_app_names}) FACET trace.id SINCE 1 hour ago LIMIT 20"
      }
    }
  }
}
