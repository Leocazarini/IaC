# Teto de gasto vigiado.
#
# Nada aqui previne cobranca — os dois recursos avisam depois que o gasto
# aconteceu. A prevencao real e o terraform destroy ao final de cada sessao.
# Neste plano de free tier isso protege o saldo de credito, nao a fatura: o
# credito e o que define quanto tempo a conta ainda tem (ver docs/04-custos.md).

# --- Orcamento mensal --------------------------------------------------------

resource "aws_budgets_budget" "monthly" {
  name         = "${local.name_prefix}-mensal"
  budget_type  = "COST"
  time_unit    = "MONTHLY"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"

  # Aviso cedo, com o gasto ainda em curso.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.billing_email]
  }

  # Aviso pela projecao: pega o gasto que ainda vai estourar o mes.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.billing_email]
  }
}

# --- Alarme de EstimatedCharges ----------------------------------------------

# A metrica EstimatedCharges so existe em us-east-1, independentemente da regiao
# do resto da infraestrutura. Dai o provider com alias: mesmo que a regiao do
# projeto mude, o alarme continua no lugar certo.

# Um alarme sem destino nao avisa ninguem. O topico e a assinatura por e-mail
# cabem na franquia gratuita do SNS.
resource "aws_sns_topic" "billing_alarm" {
  provider = aws.billing

  name = "${local.name_prefix}-billing-alarm"
}

# A assinatura nasce em estado "pending confirmation": a AWS envia um e-mail e o
# destinatario precisa clicar no link. Ate la, o alarme dispara sem entregar.
resource "aws_sns_topic_subscription" "billing_alarm" {
  provider = aws.billing

  topic_arn = aws_sns_topic.billing_alarm.arn
  protocol  = "email"
  endpoint  = var.billing_email
}

resource "aws_cloudwatch_metric_alarm" "estimated_charges" {
  provider = aws.billing

  alarm_name        = "${local.name_prefix}-estimated-charges"
  alarm_description = "Cobranca estimada da conta acima de USD ${var.billing_alarm_threshold_usd}."

  namespace   = "AWS/Billing"
  metric_name = "EstimatedCharges"
  dimensions  = { Currency = "USD" }

  # EstimatedCharges e publicada algumas vezes por dia; 6 h e o periodo util.
  statistic           = "Maximum"
  period              = 21600
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.billing_alarm_threshold_usd

  # Conta sem cobranca nenhuma nao publica a metrica. Sem isto, o alarme fica
  # em INSUFFICIENT_DATA em vez de OK, e a validacao da fase falha por engano.
  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.billing_alarm.arn]
  ok_actions    = [aws_sns_topic.billing_alarm.arn]
}
