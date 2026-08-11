output "nodes_public_ips" {
  description = "Public IPs (v4) of nodes for SSH access"
  value = {
    for k, v in hcloud_server.nodes : k => v.ipv4_address
  }
}

output "nodes_private_ips" {
  description = "Private IPs for internal debugging"
  value = {
    for k, v in hcloud_server.nodes : k => v.network[*].ip
  }
}

output "sa_public_key_pem" {
  description = "Signing public key, consumed by the AWS stack to build the JWKS."
  value       = tls_private_key.sa_signing.public_key_pem
}

output "oidc_issuer_url" {
  description = "Issuer configured on the API server."
  value       = var.oidc_issuer_url
}