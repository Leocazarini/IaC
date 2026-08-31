# Segunda parede: Network ACLs.
#
# Stateless e por subnet. Cada regra de entrada exige a regra de saida
# correspondente nas portas efemeras — esquecer isso produz uma conexao que
# estabelece e depois trava, sem erro claro.
#
# A granularidade e propositalmente mais grossa que a dos Security Groups: uma
# NACL aceita 20 regras, o que nao comporta uma entrada por range da
# Cloudflare. A restricao por origem do trafego web vive no Security Group; a
# NACL confere apenas a porta.

locals {
  # Entrada do subnet publico. Espelha o Security Group do bastion.
  public_nacl_ingress = merge(
    {
      "in-vpc"           = { number = 100, protocol = "-1", from = null, to = null, cidr = var.vpc_cidr }
      "in-wireguard"     = { number = 110, protocol = "udp", from = var.wireguard_port, to = var.wireguard_port, cidr = local.any_ipv4 }
      "in-http"          = { number = 120, protocol = "tcp", from = local.port_http, to = local.port_http, cidr = local.any_ipv4 }
      "in-https"         = { number = 130, protocol = "tcp", from = local.port_https, to = local.port_https, cidr = local.any_ipv4 }
      "in-ephemeral-tcp" = { number = 140, protocol = "tcp", from = local.ephemeral_from, to = local.ephemeral_to, cidr = local.any_ipv4 }
      "in-ephemeral-udp" = { number = 150, protocol = "udp", from = local.ephemeral_from, to = local.ephemeral_to, cidr = local.any_ipv4 }
    },
    {
      for idx, cidr in var.admin_cidr :
      "in-ssh-${idx}" => { number = 200 + idx, protocol = "tcp", from = var.ssh_port, to = var.ssh_port, cidr = cidr }
    }
  )

  # Saida do subnet publico. Alem do retorno nas portas efemeras, o bastion
  # precisa alcancar a internet em nome do subnet privado: resolucao de nome,
  # relogio, repositorio de pacote e registro de imagem.
  public_nacl_egress = {
    "out-vpc"           = { number = 100, protocol = "-1", from = null, to = null, cidr = var.vpc_cidr }
    "out-dns-udp"       = { number = 110, protocol = "udp", from = local.port_dns, to = local.port_dns, cidr = local.any_ipv4 }
    "out-dns-tcp"       = { number = 120, protocol = "tcp", from = local.port_dns, to = local.port_dns, cidr = local.any_ipv4 }
    "out-ntp"           = { number = 130, protocol = "udp", from = local.port_ntp, to = local.port_ntp, cidr = local.any_ipv4 }
    "out-http"          = { number = 140, protocol = "tcp", from = local.port_http, to = local.port_http, cidr = local.any_ipv4 }
    "out-https"         = { number = 150, protocol = "tcp", from = local.port_https, to = local.port_https, cidr = local.any_ipv4 }
    "out-ephemeral-tcp" = { number = 160, protocol = "tcp", from = local.ephemeral_from, to = local.ephemeral_to, cidr = local.any_ipv4 }
    "out-ephemeral-udp" = { number = 170, protocol = "udp", from = local.ephemeral_from, to = local.ephemeral_to, cidr = local.any_ipv4 }
  }

  # Entrada do subnet privado. O trafego web chega com o endereco de origem da
  # Cloudflare preservado, entao a faixa da VPC nao o cobre.
  private_nacl_ingress = {
    "in-vpc"           = { number = 100, protocol = "-1", from = null, to = null, cidr = var.vpc_cidr }
    "in-wireguard"     = { number = 110, protocol = "-1", from = null, to = null, cidr = var.wireguard_cidr }
    "in-http"          = { number = 120, protocol = "tcp", from = local.port_http, to = local.port_http, cidr = local.any_ipv4 }
    "in-https"         = { number = 130, protocol = "tcp", from = local.port_https, to = local.port_https, cidr = local.any_ipv4 }
    "in-ephemeral-tcp" = { number = 140, protocol = "tcp", from = local.ephemeral_from, to = local.ephemeral_to, cidr = local.any_ipv4 }
    "in-ephemeral-udp" = { number = 150, protocol = "udp", from = local.ephemeral_from, to = local.ephemeral_to, cidr = local.any_ipv4 }
  }

  private_nacl_egress = {
    "out-vpc"           = { number = 100, protocol = "-1", from = null, to = null, cidr = var.vpc_cidr }
    "out-wireguard"     = { number = 110, protocol = "-1", from = null, to = null, cidr = var.wireguard_cidr }
    "out-dns-udp"       = { number = 120, protocol = "udp", from = local.port_dns, to = local.port_dns, cidr = local.any_ipv4 }
    "out-dns-tcp"       = { number = 130, protocol = "tcp", from = local.port_dns, to = local.port_dns, cidr = local.any_ipv4 }
    "out-ntp"           = { number = 140, protocol = "udp", from = local.port_ntp, to = local.port_ntp, cidr = local.any_ipv4 }
    "out-http"          = { number = 150, protocol = "tcp", from = local.port_http, to = local.port_http, cidr = local.any_ipv4 }
    "out-https"         = { number = 160, protocol = "tcp", from = local.port_https, to = local.port_https, cidr = local.any_ipv4 }
    "out-ephemeral-tcp" = { number = 170, protocol = "tcp", from = local.ephemeral_from, to = local.ephemeral_to, cidr = local.any_ipv4 }
    "out-ephemeral-udp" = { number = 180, protocol = "udp", from = local.ephemeral_from, to = local.ephemeral_to, cidr = local.any_ipv4 }
  }
}

resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = [aws_subnet.public.id]

  tags = { Name = "${local.name_prefix}-public" }
}

resource "aws_network_acl" "private" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = [aws_subnet.private.id]

  tags = { Name = "${local.name_prefix}-private" }
}

resource "aws_network_acl_rule" "public_ingress" {
  for_each = local.public_nacl_ingress

  network_acl_id = aws_network_acl.public.id
  rule_number    = each.value.number
  egress         = false
  protocol       = each.value.protocol
  rule_action    = "allow"
  cidr_block     = each.value.cidr
  from_port      = each.value.from
  to_port        = each.value.to
}

resource "aws_network_acl_rule" "public_egress" {
  for_each = local.public_nacl_egress

  network_acl_id = aws_network_acl.public.id
  rule_number    = each.value.number
  egress         = true
  protocol       = each.value.protocol
  rule_action    = "allow"
  cidr_block     = each.value.cidr
  from_port      = each.value.from
  to_port        = each.value.to
}

resource "aws_network_acl_rule" "private_ingress" {
  for_each = local.private_nacl_ingress

  network_acl_id = aws_network_acl.private.id
  rule_number    = each.value.number
  egress         = false
  protocol       = each.value.protocol
  rule_action    = "allow"
  cidr_block     = each.value.cidr
  from_port      = each.value.from
  to_port        = each.value.to
}

resource "aws_network_acl_rule" "private_egress" {
  for_each = local.private_nacl_egress

  network_acl_id = aws_network_acl.private.id
  rule_number    = each.value.number
  egress         = true
  protocol       = each.value.protocol
  rule_action    = "allow"
  cidr_block     = each.value.cidr
  from_port      = each.value.from
  to_port        = each.value.to
}
