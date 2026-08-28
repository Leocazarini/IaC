# Modulo de compute na AWS.
#
# Este e o unico lugar do repositorio que referencia recursos AWS. Tudo que o
# consome — o inventario do Ansible e o modulo cloudflare — enxerga apenas o
# contrato de saidas declarado em outputs.tf.
#
# Trocar de provedor significa escrever um modulo irmao que exponha as mesmas
# saidas; nada fora daqui muda.

locals {
  # Hostname no formato [ambiente]-[funcao]-[local]-[numero].
  bastion_hostname = "${var.environment}-bastion-${var.location_code}-01"
  app_hostname     = "${var.environment}-app-${var.location_code}-01"

  # Prefixo dos nomes de recurso, para leitura no console e nos filtros de custo.
  name_prefix = "${var.project}-${var.environment}"
}

# Instancias, criptografia em repouso e auditoria
# (implementacao na proxima fase)
