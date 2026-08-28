# --- Identificacao -----------------------------------------------------------

variable "project" {
  description = "Nome do projeto. Compoe o nome dos recursos e a tag Project."
  type        = string
}

variable "environment" {
  description = "Nome do ambiente. Compoe o hostname e a tag Env."
  type        = string
}

variable "region" {
  description = "Regiao AWS onde a infraestrutura e criada."
  type        = string
}

variable "location_code" {
  description = "Codigo curto da regiao usado no hostname. Exemplo: use1 para us-east-1."
  type        = string
}

# --- Rede --------------------------------------------------------------------

variable "availability_zone" {
  description = <<-EOT
    Zona de disponibilidade dos dois subnets. Ambos ficam na mesma zona: o
    trafego entre o bastion e o host de aplicacao e cobrado entre zonas.
    Nulo usa a primeira zona disponivel da regiao.
  EOT
  type        = string
  default     = null
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Bloco CIDR do subnet publico, o unico com rota para o Internet Gateway."
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "Bloco CIDR do subnet privado. Sai para a internet pela ENI do bastion."
  type        = string
  default     = "10.0.11.0/24"
}

variable "wireguard_cidr" {
  description = "Bloco CIDR da rede WireGuard. Nao pode se sobrepor ao CIDR da VPC."
  type        = string
  default     = "10.8.0.0/24"
}

variable "wireguard_port" {
  description = "Porta UDP em que o servidor WireGuard escuta no bastion."
  type        = number
  default     = 51820
}

variable "bastion_private_ip" {
  description = "IP fixo do bastion dentro do subnet publico. Referenciado na rota de saida do subnet privado."
  type        = string
  default     = "10.0.1.10"
}

variable "app_private_ip" {
  description = "IP fixo do host de aplicacao dentro do subnet privado. Referenciado no inventario do Ansible."
  type        = string
  default     = "10.0.11.10"
}

variable "admin_cidr" {
  description = <<-EOT
    Origem autorizada a abrir SSH no bastion durante a janela de bootstrap.
    Lista vazia remove a regra do Security Group, que e o estado definitivo
    depois que o tunel WireGuard sobe.
    Minimo: o IP publico do operador com mascara /32 | Recomendado: lista vazia
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.admin_cidr, "0.0.0.0/0")
    error_message = "admin_cidr nao pode ser 0.0.0.0/0: a janela de bootstrap precisa ser restrita a um endereco conhecido."
  }
}

variable "cloudflare_ipv4_url" {
  description = "Endereco da lista de ranges IPv4 publicados pela Cloudflare, lida em tempo de plano."
  type        = string
  default     = "https://www.cloudflare.com/ips-v4"
}

# --- Acesso ------------------------------------------------------------------

variable "ssh_user" {
  description = "Usuario administrativo criado no host e usado pelo Ansible."
  type        = string
  default     = "ops"
}

variable "ssh_port" {
  description = "Porta em que o servidor SSH escuta apos o hardening."
  type        = number
  default     = 22
}

variable "ssh_public_key" {
  description = "Chave publica SSH autorizada no usuario administrativo."
  type        = string
  default     = null
}

# --- Instancias --------------------------------------------------------------

variable "bastion_instance_type" {
  description = "Tipo da instancia do bastion. Acumula NAT e servidor WireGuard."
  type        = string
  default     = "t4g.nano"
}

variable "app_instance_type" {
  description = "Tipo da instancia de aplicacao."
  type        = string
  default     = "t3.micro"
}

variable "bastion_root_volume_size" {
  description = "Tamanho em GB do volume raiz do bastion."
  type        = number
  default     = 8
}

variable "app_root_volume_size" {
  description = "Tamanho em GB do volume raiz do host de aplicacao."
  type        = number
  default     = 20
}

# --- Custo -------------------------------------------------------------------

variable "billing_email" {
  description = "Endereco que recebe as notificacoes de orcamento e o alarme de cobranca. Vem do terraform.tfvars, que e gitignored."
  type        = string

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.billing_email))
    error_message = "billing_email precisa ser um endereco de e-mail valido: sem ele o orcamento e o alarme nao avisam ninguem."
  }
}

variable "budget_limit_usd" {
  description = "Teto do orcamento mensal em USD. Notifica em 80% do realizado e em 100% da projecao."
  type        = number
  default     = 10
}

variable "billing_alarm_threshold_usd" {
  description = "Valor de EstimatedCharges acima do qual o alarme dispara, em USD."
  type        = number
  default     = 10
}
