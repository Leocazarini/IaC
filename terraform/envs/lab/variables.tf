# --- Identificacao -----------------------------------------------------------

variable "project" {
  description = "Nome do projeto. Compoe o nome dos recursos e a tag Project."
  type        = string
  default     = "vps-infra"
}

variable "environment" {
  description = "Nome do ambiente."
  type        = string
  default     = "lab"
}

variable "phase" {
  description = "Fase que criou ou alterou os recursos por ultimo. Preenche a tag Phase."
  type        = string
  default     = "c1f2"
}

variable "region" {
  description = "Regiao AWS onde a infraestrutura e criada."
  type        = string
}

variable "location_code" {
  description = "Codigo curto da regiao usado no hostname. Exemplo: use1 para us-east-1."
  type        = string
}

# --- Acesso ------------------------------------------------------------------

variable "admin_cidr" {
  description = <<-EOT
    Origem autorizada a abrir SSH no bastion durante a janela de bootstrap.
    Esvaziar depois que o tunel WireGuard estiver de pe e reaplicar.
  EOT
  type        = list(string)
  default     = []
}

variable "ssh_public_key" {
  description = "Chave publica SSH autorizada no usuario administrativo."
  type        = string
  default     = null
}

# --- Custo -------------------------------------------------------------------

variable "billing_email" {
  description = "Endereco que recebe as notificacoes de orcamento e o alarme de cobranca."
  type        = string
}

variable "budget_limit_usd" {
  description = "Teto do orcamento mensal em USD."
  type        = number
  default     = 10
}

# --- Borda publica -----------------------------------------------------------

variable "cloudflare_zone_id" {
  description = "Identificador da zona Cloudflare do dominio."
  type        = string
  default     = null
}

variable "domain" {
  description = "Dominio raiz gerenciado na Cloudflare."
  type        = string
  default     = null
}
