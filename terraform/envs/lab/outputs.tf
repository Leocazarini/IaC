# Saidas consumidas por scripts/gen-inventory.sh para montar o inventario do
# Ansible. Os nomes espelham o contrato do modulo de compute.
#
# public_ip e instance_id so passam a ter valor na Fase 2.1, quando a instancia
# bastion existe. A fiacao ja existe para que o contrato nao mude depois.

output "public_ip" {
  description = "Endereco IPv4 publico do bastion."
  value       = module.compute.public_ip
}

output "ssh_user" {
  description = "Usuario de conexao inicial usado pelo Ansible."
  value       = module.compute.ssh_user
}

output "ssh_port" {
  description = "Porta efetiva do servidor SSH."
  value       = module.compute.ssh_port
}

output "instance_id" {
  description = "Identificador da instancia bastion no provedor."
  value       = module.compute.instance_id
}
