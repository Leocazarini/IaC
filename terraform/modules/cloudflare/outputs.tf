output "fqdns" {
  description = "Nomes totalmente qualificados publicados na zona."
  value       = [] # (implementacao na proxima fase)
}

output "proxied" {
  description = "Indica se o trafego passa pelo proxy da Cloudflare. Define se o Security Group da aplicacao deve restringir 80/443 aos ranges da Cloudflare."
  value       = var.proxied
}
