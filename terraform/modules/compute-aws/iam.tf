# Identidade das instancias.
#
# Cada instancia recebe uma role propria e um instance profile proprio. O
# profile existe desde a Fase 1.1, antes de qualquer instancia, porque associar
# um profile a uma instancia ja criada exige recria-la — e porque e ele que
# torna possivel, mais adiante, ler do Parameter Store sem colocar uma chave em
# arquivo dentro do host.
#
# Privilegio minimo escrito a mao: nunca AdministratorAccess, nunca
# PowerUserAccess. Permissao nova entra na fase que precisar dela, nunca
# antecipada "por precaucao".

data "aws_caller_identity" "current" {}

locals {
  # As duas identidades da infraestrutura. O bastion acumula NAT e WireGuard
  # (ADR-006); o app roda a plataforma de containers.
  instance_roles = {
    bastion = "Instancia bastion: NAT, servidor WireGuard e ponto de entrada administrativo"
    app     = "Instancia de aplicacao no subnet privado"
  }

  # Prefixo dos caminhos do Parameter Store. Cada role le apenas a propria
  # subarvore: /vps-infra/lab/bastion/* nao e visivel para o host de aplicacao.
  ssm_path_prefix = "/${var.project}/${var.environment}"
}

# --- Roles e instance profiles -----------------------------------------------

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    sid     = "EC2AssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  for_each = local.instance_roles

  name               = "${local.name_prefix}-${each.key}"
  description        = each.value
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_instance_profile" "instance" {
  for_each = local.instance_roles

  name = "${local.name_prefix}-${each.key}"
  role = aws_iam_role.instance[each.key].name
}

# --- Politica de privilegio minimo -------------------------------------------

data "aws_iam_policy_document" "instance" {
  for_each = local.instance_roles

  # Leitura restrita a subarvore do proprio papel dentro do proprio ambiente.
  # Consumida a partir da Camada 5, quando ha segredo de aplicacao para ler.
  statement {
    sid    = "ReadOwnParameters"
    effect = "Allow"

    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]

    resources = [
      "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${local.ssm_path_prefix}/${each.key}/*",
    ]
  }

  # Escrita de log no CloudWatch, restrita aos grupos do proprio ambiente. O
  # grupo dos Flow Logs fica deliberadamente fora deste prefixo: registro que a
  # instancia monitorada consegue escrever nao serve como evidencia.
  statement {
    sid    = "WriteOwnLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]

    resources = [
      "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:${local.ssm_path_prefix}/*",
    ]
  }
}

resource "aws_iam_policy" "instance" {
  for_each = local.instance_roles

  name        = "${local.name_prefix}-${each.key}"
  description = "Privilegio minimo da instancia ${each.key}: Parameter Store do proprio papel e escrita de log."
  policy      = data.aws_iam_policy_document.instance[each.key].json
}

resource "aws_iam_role_policy_attachment" "instance" {
  for_each = local.instance_roles

  role       = aws_iam_role.instance[each.key].name
  policy_arn = aws_iam_policy.instance[each.key].arn
}
