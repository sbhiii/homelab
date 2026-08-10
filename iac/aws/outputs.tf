output "zone_nameservers" {
  description = "Create these as NS records at Cloudflare to delegate the subdomain."
  value       = aws_route53_zone.homelab.name_servers
}

output "hosted_zone_id" {
  description = "Zone ID for the cert-manager solver and the IAM policy."
  value       = aws_route53_zone.homelab.zone_id
}

output "issuer_url" {
  description = "OIDC issuer URL."
  value       = local.issuer_url
}
