# Saidas consumidas por scripts/gen-inventory.sh para montar o inventario do
# Ansible. Os nomes espelham o contrato do modulo de compute.

output "public_ip" {
  description = "Endereco IPv4 publico do bastion."
  value       = null # (implementacao na proxima fase)
}

output "ssh_user" {
  description = "Usuario de conexao inicial usado pelo Ansible."
  value       = null # (implementacao na proxima fase)
}

output "ssh_port" {
  description = "Porta efetiva do servidor SSH."
  value       = null # (implementacao na proxima fase)
}

output "instance_id" {
  description = "Identificador da instancia bastion no provedor."
  value       = null # (implementacao na proxima fase)
}
