terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }

  # Estado local, fora do versionamento. Um operador, uma maquina, sem
  # concorrencia — ver ADR-005. Migrar para backend remoto e um unico comando:
  # terraform init -migrate-state
  backend "local" {
    path = "terraform.tfstate"
  }
}
