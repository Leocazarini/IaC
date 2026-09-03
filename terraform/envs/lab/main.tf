# Ambiente lab: descartavel por natureza. Criado no inicio de uma sessao de
# teste, validado e destruido ao final.

# Infraestrutura de compute, identidade, controle de gasto e auditoria.
#
# O alias de billing e repassado explicitamente: e nele que vive o alarme de
# EstimatedCharges, que so existe em us-east-1.
module "compute" {
  source = "../../modules/compute-aws"

  providers = {
    aws         = aws
    aws.billing = aws.billing
  }

  project       = var.project
  environment   = var.environment
  region        = var.region
  location_code = var.location_code

  admin_cidr     = var.admin_cidr
  ssh_public_key = var.ssh_public_key

  billing_email    = var.billing_email
  budget_limit_usd = var.budget_limit_usd

  trail_bucket_force_destroy = var.trail_bucket_force_destroy
}

# Borda publica
# (implementacao na Fase 4.1)
