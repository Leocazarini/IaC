# Contrato anti-lock-in.
#
# Estas quatro saidas sao a unica superficie do modulo. Qualquer modulo de
# compute de outro provedor precisa expor exatamente estas, com os mesmos tipos.
# Adicionar saida aqui e ampliar o contrato: so com motivo registrado em
# docs/03-decisoes.md.

output "public_ip" {
  description = "Endereco IPv4 publico do bastion. Alvo dos registros DNS e ponto de entrada do tunel administrativo."
  value       = null # (implementacao na proxima fase)
}

output "ssh_user" {
  description = "Usuario de conexao inicial usado pelo Ansible."
  value       = var.ssh_user
}

output "ssh_port" {
  description = "Porta efetiva do servidor SSH."
  value       = var.ssh_port
}

output "instance_id" {
  description = "Identificador da instancia bastion no provedor."
  value       = null # (implementacao na proxima fase)
}
