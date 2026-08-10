# Clé de signature des tokens ServiceAccount.
#
# Elle vit dans le state, pas sur le noeud : un changement de user_data
# remplace le serveur mais laisse cette ressource intacte, donc le JWKS publié
# et la confiance AWS survivent aux reconstructions.
resource "tls_private_key" "sa_signing" {
  algorithm = "RSA"
  rsa_bits  = 2048
}
