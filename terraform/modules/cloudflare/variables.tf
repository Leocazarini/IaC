variable "zone_id" {
  description = "Identificador da zona Cloudflare do dominio."
  type        = string
}

variable "domain" {
  description = "Dominio raiz gerenciado nesta zona."
  type        = string
}

variable "origin_ip" {
  description = <<-EOT
    Endereco IPv4 de origem para onde os registros apontam.
    Consome apenas a saida public_ip do modulo de compute; nenhum recurso do
    provedor de compute e referenciado aqui.
  EOT
  type        = string
}

variable "records" {
  description = "Subdominios publicados na zona. O registro raiz e criado sempre; esta lista e adicional."
  type        = list(string)
  default     = []
}

variable "proxied" {
  description = <<-EOT
    Passa o trafego pelo proxy da Cloudflare.
    Minimo: false enquanto a origem nao responde com certificado valido | Recomendado: true
  EOT
  type        = bool
  default     = false
}

variable "ssl_mode" {
  description = <<-EOT
    Modo de validacao TLS entre a Cloudflare e a origem.
    Minimo: full | Recomendado: strict
  EOT
  type        = string
  default     = "full"

  validation {
    condition     = contains(["full", "strict"], var.ssl_mode)
    error_message = "ssl_mode aceita apenas full ou strict: os modos off e flexible deixam o trafego ate a origem sem criptografia."
  }
}
