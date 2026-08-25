# Credenciais vem do perfil do aws-cli, nunca do codigo.
provider "aws" {
  region = var.region

  # Aplicadas a todo recurso que aceite tags, para nao repetir em cada bloco.
  default_tags {
    tags = {
      Project   = var.project
      Env       = var.environment
      Phase     = var.phase
      ManagedBy = "terraform"
    }
  }
}

# O alarme de EstimatedCharges so existe em us-east-1, independentemente da
# regiao do resto da infraestrutura.
provider "aws" {
  alias  = "billing"
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = var.project
      Env       = var.environment
      Phase     = var.phase
      ManagedBy = "terraform"
    }
  }
}

# O token vem da variavel de ambiente CLOUDFLARE_API_TOKEN.
provider "cloudflare" {}
