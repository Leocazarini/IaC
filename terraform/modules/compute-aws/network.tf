# Perimetro da rede.
#
# Duas paredes. O Security Group e stateful e vale por instancia: e a fonte da
# verdade sobre o que pode entrar. A Network ACL e stateless e vale por subnet:
# e a segunda parede, mais grossa, que segura um erro de configuracao no
# Security Group. Divergencia entre as duas e bug, nao defesa em profundidade.

data "aws_availability_zones" "available" {
  state = "available"
}

# Ranges de IP publicados pela Cloudflare, lidos em tempo de plano. Eles mudam
# sem aviso; uma lista fixa no codigo vira uma borda que para de funcionar.
data "http" "cloudflare_ipv4" {
  url = var.cloudflare_ipv4_url

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "A lista de ranges da Cloudflare respondeu HTTP ${self.status_code}. Sem ela as regras de 80/443 do host de aplicacao ficariam sem origem."
    }
  }
}

locals {
  availability_zone = coalesce(var.availability_zone, data.aws_availability_zones.available.names[0])

  # Sufixo do nome do subnet: a letra da zona de disponibilidade.
  az_suffix = substr(local.availability_zone, -1, 1)

  any_ipv4 = "0.0.0.0/0"

  cloudflare_ipv4 = compact(split("\n", trimspace(data.http.cloudflare_ipv4.response_body)))

  # Portas efemeras. Como a NACL e stateless, toda regra de entrada precisa da
  # regra de saida correspondente nesta faixa. Faltando uma, a conexao
  # estabelece e trava depois, sem erro claro.
  ephemeral_from = 1024
  ephemeral_to   = 65535

  # Constantes de protocolo usadas nas regras de saida das NACLs.
  port_dns   = 53
  port_ntp   = 123
  port_http  = 80
  port_https = 443
}

# --- VPC e subnets -----------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  # Necessario para que as instancias resolvam e recebam nome DNS interno.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name_prefix}-vpc" }
}

# Unico subnet com rota para o Internet Gateway.
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidr
  availability_zone = local.availability_zone

  # O bastion recebe um Elastic IP explicito. Endereco publico automatico
  # criaria um segundo IP, efemero e fora do alcance do registro DNS.
  map_public_ip_on_launch = false

  tags = { Name = "${local.name_prefix}-public-${local.az_suffix}" }
}

# Sem rota para o Internet Gateway e sem endereco publico: a saida e pela ENI
# do bastion.
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = local.availability_zone

  map_public_ip_on_launch = false

  tags = { Name = "${local.name_prefix}-private-${local.az_suffix}" }
}

# --- Roteamento --------------------------------------------------------------

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = local.any_ipv4
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${local.name_prefix}-public" }
}

# Tabela sem rota default. O subnet privado alcanca apenas a propria VPC ate
# que a rota 0.0.0.0/0 aponte para a ENI do bastion
# (implementacao na proxima fase).
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-private" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# --- Security group do bastion -----------------------------------------------

resource "aws_security_group" "bastion" {
  name        = "${local.name_prefix}-bastion"
  description = "Bastion: tunel WireGuard, janela de bootstrap por SSH e trafego roteado do subnet privado"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-bastion" }
}

# A origem e aberta porque o peer administrativo se conecta de onde estiver. O
# que autentica e a chave do WireGuard, nao o endereco de origem.
resource "aws_vpc_security_group_ingress_rule" "bastion_wireguard" {
  security_group_id = aws_security_group.bastion.id
  description       = "Tunel WireGuard"

  cidr_ipv4   = local.any_ipv4
  ip_protocol = "udp"
  from_port   = var.wireguard_port
  to_port     = var.wireguard_port
}

# Janela de bootstrap. Lista vazia em admin_cidr faz a regra desaparecer, que e
# o estado definitivo depois que o tunel esta de pe.
# Minimo: o IP publico do operador com mascara /32 | Recomendado: lista vazia
resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  for_each = toset(var.admin_cidr)

  security_group_id = aws_security_group.bastion.id
  description       = "SSH da janela de bootstrap"

  cidr_ipv4   = each.value
  ip_protocol = "tcp"
  from_port   = var.ssh_port
  to_port     = var.ssh_port
}

# O bastion roteia a saida do subnet privado. O trafego do host de aplicacao
# chega pela ENI do bastion e e avaliado pelo Security Group dele: sem esta
# regra o NAT nao encaminha nada.
resource "aws_vpc_security_group_ingress_rule" "bastion_from_private" {
  security_group_id = aws_security_group.bastion.id
  description       = "Trafego do subnet privado roteado pelo NAT"

  cidr_ipv4   = var.private_subnet_cidr
  ip_protocol = "-1"
}

resource "aws_vpc_security_group_egress_rule" "bastion_all" {
  security_group_id = aws_security_group.bastion.id
  description       = "Saida liberada: o bastion roteia o trafego do subnet privado"

  cidr_ipv4   = local.any_ipv4
  ip_protocol = "-1"
}

# --- Security group do host de aplicacao -------------------------------------

resource "aws_security_group" "app" {
  name        = "${local.name_prefix}-app"
  description = "Host de aplicacao: SSH apenas pela rede WireGuard e trafego web apenas dos ranges da Cloudflare"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-app" }
}

resource "aws_vpc_security_group_ingress_rule" "app_ssh" {
  security_group_id = aws_security_group.app.id
  description       = "SSH pela rede WireGuard"

  cidr_ipv4   = var.wireguard_cidr
  ip_protocol = "tcp"
  from_port   = var.ssh_port
  to_port     = var.ssh_port
}

resource "aws_vpc_security_group_ingress_rule" "app_http" {
  for_each = toset(local.cloudflare_ipv4)

  security_group_id = aws_security_group.app.id
  description       = "HTTP da Cloudflare"

  cidr_ipv4   = each.value
  ip_protocol = "tcp"
  from_port   = local.port_http
  to_port     = local.port_http
}

resource "aws_vpc_security_group_ingress_rule" "app_https" {
  for_each = toset(local.cloudflare_ipv4)

  security_group_id = aws_security_group.app.id
  description       = "HTTPS da Cloudflare"

  cidr_ipv4   = each.value
  ip_protocol = "tcp"
  from_port   = local.port_https
  to_port     = local.port_https
}

resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  description       = "Saida liberada: atualizacao de pacote e pull de imagem pelo NAT"

  cidr_ipv4   = local.any_ipv4
  ip_protocol = "-1"
}
