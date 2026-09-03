# Auditoria da conta e da rede.
#
# Duas trilhas independentes, com propositos diferentes: o CloudTrail registra
# chamadas de API — quem pediu o que a AWS, de onde e quando — e os Flow Logs
# registram o que a rede descartou. A primeira responde "quem mexeu"; a segunda,
# "o que tentou entrar".
#
# Ambas existem antes de haver instancia. Ligar auditoria depois de algo
# acontecer perde exatamente o periodo mais interessante.

locals {
  trail_name = "${local.name_prefix}-trail"

  # O nome do bucket e global: o identificador da conta e o que garante que ele
  # nao colide com o de outra pessoa.
  trail_bucket_name = "${local.name_prefix}-cloudtrail-${data.aws_caller_identity.current.account_id}"

  # O ARN do trail e montado a mao, e nao lido de aws_cloudtrail.main.arn, para
  # nao criar ciclo: a politica do bucket precisa existir antes do trail, e o
  # trail so entrega no bucket que a politica autorizou.
  trail_arn = "arn:aws:cloudtrail:${var.region}:${data.aws_caller_identity.current.account_id}:trail/${local.trail_name}"
}

# --- Bucket do CloudTrail ----------------------------------------------------

resource "aws_s3_bucket" "trail" {
  bucket = local.trail_bucket_name

  # Um bucket com objetos dentro sobrevive ao destroy quando isto e falso, e o
  # que sobra e um recurso orfao que reaparece na fatura meses depois.
  force_destroy = var.trail_bucket_force_destroy
}

# Registro de auditoria em bucket legivel de fora nao e registro de auditoria.
# As quatro travas juntas: nem ACL nem policy conseguem torna-lo publico.
resource "aws_s3_bucket_public_access_block" "trail" {
  bucket = aws_s3_bucket.trail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versionamento preserva o objeto original quando algo o sobrescreve.
resource "aws_s3_bucket_versioning" "trail" {
  bucket = aws_s3_bucket.trail.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Criptografia em repouso do proprio registro, com a chave gerenciada pelo S3.
# Declarada explicitamente para que uma mudanca no padrao da conta apareca como
# diferenca no plan em vez de passar despercebida.
resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Sem expiracao, o bucket cresce para sempre. Com versionamento ligado, expirar
# so a versao corrente nao libera espaco nenhum: a versao antiga fica.
resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id

  rule {
    id     = "expira-registros-antigos"
    status = "Enabled"

    # Filtro vazio: a regra vale para todo objeto do bucket.
    filter {}

    expiration {
      days = var.trail_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.trail_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.trail]
}

# Escrita liberada apenas ao servico CloudTrail, e apenas em nome deste trail:
# sem a condicao de origem, qualquer trail de qualquer conta poderia pedir ao
# servico que entregasse aqui.
data "aws_iam_policy_document" "trail_bucket" {
  statement {
    sid       = "CloudTrailAclCheck"
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.trail.arn]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  statement {
    sid       = "CloudTrailWrite"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.trail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  bucket = aws_s3_bucket.trail.id
  policy = data.aws_iam_policy_document.trail_bucket.json

  # A policy so tem efeito com o bloqueio de acesso publico ja no lugar.
  depends_on = [aws_s3_bucket_public_access_block.trail]
}

# --- Trail -------------------------------------------------------------------

resource "aws_cloudtrail" "main" {
  name           = local.trail_name
  s3_bucket_name = aws_s3_bucket.trail.id

  # Um unico trail cobrindo todas as regioes, inclusive as que o projeto nao
  # usa: atividade em regiao inesperada e justamente o que se quer enxergar.
  is_multi_region_trail = true

  # IAM, STS e as demais APIs globais so publicam evento em us-east-1.
  include_global_service_events = true

  # Cada arquivo entregue ganha um digest assinado, que permite provar depois
  # que o registro nao foi alterado nem removido.
  enable_log_file_validation = true

  # Sem event_selector: apenas management events, que e o trail sem cobranca.
  # Data events de S3 e Lambda sao cobrados por evento registrado.

  depends_on = [aws_s3_bucket_policy.trail]
}

# --- Flow Logs da VPC --------------------------------------------------------

# O log group fica fora do prefixo que as roles de instancia podem escrever
# (ver iam.tf): registro que a propria instancia monitorada consegue adulterar
# nao serve como evidencia.
resource "aws_cloudwatch_log_group" "flow_log" {
  name = "/aws/vpc/flow-logs/${local.name_prefix}"

  # Retencao curta para caber nos 5 GB gratuitos do CloudWatch. Sem isto o
  # grupo nasce como "never expire" e a franquia acaba silenciosamente.
  retention_in_days = var.flow_log_retention_days
}

# Quem escreve no log group e o servico, nao a instancia. A role existe so para
# isso, e as duas condicoes impedem que um flow log de outra conta a use.
data "aws_iam_policy_document" "flow_log_assume_role" {
  statement {
    sid     = "FlowLogsAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:vpc-flow-log/*"]
    }
  }
}

data "aws_iam_policy_document" "flow_log" {
  statement {
    sid    = "WriteFlowLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
      "logs:DescribeLogGroups",
    ]

    resources = [
      aws_cloudwatch_log_group.flow_log.arn,
      "${aws_cloudwatch_log_group.flow_log.arn}:*",
    ]
  }
}

resource "aws_iam_role" "flow_log" {
  name               = "${local.name_prefix}-flow-log"
  description        = "Permite ao servico de Flow Logs escrever no log group da VPC"
  assume_role_policy = data.aws_iam_policy_document.flow_log_assume_role.json
}

resource "aws_iam_role_policy" "flow_log" {
  name   = "${local.name_prefix}-flow-log"
  role   = aws_iam_role.flow_log.id
  policy = data.aws_iam_policy_document.flow_log.json
}

resource "aws_flow_log" "main" {
  vpc_id = aws_vpc.main.id

  # Apenas o trafego descartado. Capturar ALL estoura os 5 GB gratuitos do
  # CloudWatch depressa, e o trafego aceito ja aparece nos logs da aplicacao.
  traffic_type = "REJECT"

  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_log.arn
  iam_role_arn         = aws_iam_role.flow_log.arn

  tags = { Name = "${local.name_prefix}-flow-log" }
}
