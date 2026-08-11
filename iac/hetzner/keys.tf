# ServiceAccount token-signing key.
#
# It lives in the state, not on the node: a user_data change replaces the server
# but leaves this resource untouched, so the published JWKS and the AWS trust
# relationship both survive node rebuilds.
resource "tls_private_key" "sa_signing" {
  algorithm = "RSA"
  rsa_bits  = 2048
}
