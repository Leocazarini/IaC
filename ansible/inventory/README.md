# Inventário

`hosts.yml` é **gerado**, não editado à mão, e é gitignored. Ele sai do output
do Terraform:

```bash
scripts/gen-inventory.sh
```

O script lê `terraform output -json` do ambiente `lab` e escreve os grupos
`bastion` e `app`. O host de aplicação não tem endereço público: o inventário o
alcança pelo IP privado, o que exige o túnel WireGuard de pé, ou por `ProxyJump`
através do bastion quando a execução for não interativa.
