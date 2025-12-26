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