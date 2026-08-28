terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
      # O alarme de EstimatedCharges so existe em us-east-1. O env repassa uma
      # segunda configuracao do provider fixada la.
      configuration_aliases = [aws.billing]
    }
    # Usado para obter os ranges de IP publicados pela Cloudflare em tempo de
    # plano, em vez de fixa-los no codigo.
    http = {
      source  = "hashicorp/http"
      version = "~> 3.5"
    }
  }
}
