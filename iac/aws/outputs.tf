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

output "discovery_bucket" {
  description = "Private S3 bucket holding the OIDC discovery documents."
  value       = aws_s3_bucket.discovery.id
}

output "discovery_distribution_domain" {
  description = "CloudFront domain fronting the discovery bucket."
  value       = aws_cloudfront_distribution.oidc.domain_name
}

output "cert_manager_role_arn" {
  description = "Role the cert-manager ServiceAccount assumes."
  value       = aws_iam_role.cert_manager.arn
}

output "apps_wildcard_target" {
  description = "IP vers laquelle *.srehomelab.sbhi.io résout."
  value       = local.node_public_ip
}
