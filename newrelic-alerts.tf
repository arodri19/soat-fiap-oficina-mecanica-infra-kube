resource "newrelic_alert_policy" "order_processing" {
  name                = "${var.project_name}-${var.environment}-order-processing"
  incident_preference = "PER_CONDITION"
}

# Dispara quando erros nas rotas de ordens de serviço (criação, atualização de
# status, anexação de serviço/peça) ultrapassam o limite — cobre o requisito
# de "alertas para falhas no processamento de ordens de serviço".
resource "newrelic_nrql_alert_condition" "order_processing_errors" {
  policy_id = newrelic_alert_policy.order_processing.id
  type      = "static"
  name      = "Falhas no processamento de ordens de servico"
  enabled   = true

  nrql {
    query = "SELECT count(*) FROM TransactionError WHERE appName = '${var.newrelic_app_name}' AND request.uri LIKE '%/orders%'"
  }

  critical {
    operator              = "above"
    threshold             = 5
    threshold_duration    = 300
    threshold_occurrences = "at_least_once"
  }

  warning {
    operator              = "above"
    threshold             = 1
    threshold_duration    = 300
    threshold_occurrences = "at_least_once"
  }

  fill_option = "none"
}

resource "newrelic_notification_destination" "email" {
  name = "${var.project_name}-${var.environment}-email"
  type = "EMAIL"

  property {
    key   = "email"
    value = var.newrelic_notification_email
  }
}

resource "newrelic_notification_channel" "email" {
  name           = "${var.project_name}-${var.environment}-email-channel"
  type           = "EMAIL"
  destination_id = newrelic_notification_destination.email.id
  product        = "IINT"

  property {
    key   = "subject"
    value = "Alerta oficina-mecanica: {{issueTitle}}"
  }
}

resource "newrelic_workflow" "order_processing" {
  name                  = "${var.project_name}-${var.environment}-order-processing-workflow"
  muting_rules_handling = "NOTIFY_ALL_ISSUES"

  issues_filter {
    name = "order-processing-filter"
    type = "FILTER"

    predicate {
      attribute = "labels.policyIds"
      operator  = "EXACTLY_MATCHES"
      values    = [newrelic_alert_policy.order_processing.id]
    }
  }

  destination {
    channel_id = newrelic_notification_channel.email.id
  }
}
