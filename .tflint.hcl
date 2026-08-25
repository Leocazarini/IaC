# Analise estatica dos modulos Terraform. Roda no pre-commit.

config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
