# The zone itself is deliberately not defined here. It belongs to the landing
# zone repository, which owns it because destroying it means correcting the NS
# records by hand at the external DNS provider, and that manual step makes it a
# durable asset rather than one following this cluster's lifecycle. This module
# owns the records inside the zone. See decision 14 in sbhi-aws-landing-zone.
#
# Looked up by name rather than read out of the landing zone's remote state. A
# name is a stable contract; a state file is an implementation detail, and
# sharing one would let a failed apply in either repository block the other.
#
# private_zone is pinned because the lookup fails on ambiguity, and a private
# zone of the same name appearing later would otherwise break this silently.
data "aws_route53_zone" "homelab" {
  name         = var.dns_zone_name
  private_zone = false
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

  zone_id         = data.aws_route53_zone.homelab.zone_id
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
