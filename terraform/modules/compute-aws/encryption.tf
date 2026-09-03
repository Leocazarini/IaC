# Criptografia em repouso.
#
# A configuracao vale para a regiao inteira, nao para um recurso: todo volume
# EBS e todo snapshot criados a partir daqui nascem criptografados, sem que a
# instancia precise pedir nada. Por isso ela nao aparece no plan associada a
# nenhuma instancia — o que nao significa que nao foi aplicada.
#
# Volumes criados antes desta configuracao nao sao convertidos retroativamente.
#
# A chave e a gerenciada pela AWS (aws/ebs), sem custo de criacao nem de
# armazenamento. Uma chave gerenciada pelo cliente custa USD 1/mes e agrega
# apenas o poder de revogar; a criptografia em si e identica.

resource "aws_ebs_encryption_by_default" "main" {
  enabled = true
}
