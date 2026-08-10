resource "aws_route53_zone" "homelab" {
  name    = var.dns_zone_name
  comment = "Delegated from Cloudflare; authoritative for cluster records."
}

resource "aws_acm_certificate" "oidc" {
  provider          = aws.us_east_1
  domain_name       = local.issuer_host
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for o in aws_acm_certificate.oidc.domain_validation_options :
    o.domain_name => {
      name   = o.resource_record_name
      type   = o.resource_record_type
      record = o.resource_record_value
    }
  }

  zone_id         = aws_route53_zone.homelab.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

# Blocks until the delegation exists at Cloudflare and the CNAME resolves.
resource "aws_acm_certificate_validation" "oidc" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.oidc.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}
