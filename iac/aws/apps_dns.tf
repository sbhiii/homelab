# DNS for the applications exposed through the cluster's Ingress.
#
# A wildcard rather than one record per application: explicit records always win
# over the wildcard, so the oidc host keeps pointing at CloudFront, and
# any new application exposed through an Ingress works without touching this file.
#
# The IP comes from the hetzner stack's remote state, the same channel as the
# signing public key. Replacing the node changes the IP, so this stack must be
# re-applied to update the record.
resource "aws_route53_record" "apps_wildcard" {
  zone_id = data.aws_route53_zone.homelab.zone_id
  name    = "*.${var.dns_zone_name}"
  type    = "A"
  ttl     = 300
  records = [local.node_public_ip]
}

locals {
  # The hetzner stack exposes a map keyed by node identifier.
  node_public_ip = data.terraform_remote_state.hetzner.outputs.nodes_public_ips[var.ingress_node_id]
}
