data "external" "jwk" {
  program = ["python3", "${path.module}/scripts/pem_to_jwk.py"]
  query = {
    public_key_pem = data.terraform_remote_state.hetzner.outputs.sa_public_key_pem
  }
}

locals {
  openid_configuration = jsonencode({
    issuer                                = local.issuer_url
    jwks_uri                              = "${local.issuer_url}/openid/v1/jwks"
    authorization_endpoint                = "urn:kubernetes:programmatic_authorization"
    response_types_supported              = ["id_token"]
    subject_types_supported               = ["public"]
    id_token_signing_alg_values_supported = ["RS256"]
    claims_supported                      = ["sub", "iss"]
  })

  jwks = jsonencode({
    keys = [{
      use = "sig"
      kty = "RSA"
      alg = "RS256"
      kid = data.external.jwk.result.kid
      n   = data.external.jwk.result.n
      e   = data.external.jwk.result.e
    }]
  })
}

resource "aws_s3_bucket" "discovery" {
  bucket = "${replace(local.issuer_host, ".", "-")}-discovery"
}

resource "aws_s3_bucket_public_access_block" "discovery" {
  bucket                  = aws_s3_bucket.discovery.id
  block_public_acls       = true
  block_public_policy     = false # the CloudFront policy below is not "public"
  ignore_public_acls      = true
  restrict_public_buckets = false
}

resource "aws_s3_object" "openid_configuration" {
  bucket       = aws_s3_bucket.discovery.id
  key          = ".well-known/openid-configuration"
  content      = local.openid_configuration
  content_type = "application/json"
  etag         = md5(local.openid_configuration)
  # Borne la fenêtre de péremption : voir le commentaire sur le JWKS.
  cache_control = "public, max-age=300"
}

resource "aws_s3_object" "jwks" {
  bucket       = aws_s3_bucket.discovery.id
  key          = "openid/v1/jwks"
  content      = local.jwks
  content_type = "application/json"
  etag         = md5(local.jwks)
  # Sans ceci, la politique CachingOptimized de CloudFront garde le document
  # 24 h par défaut. Si la clé change, STS continuerait à lire l'ancien JWKS et
  # rejetterait tous les tokens, avec une erreur peu explicite. 5 minutes borne
  # la panne sans pour autant marteler l'origine.
  cache_control = "public, max-age=300"
}

resource "aws_cloudfront_origin_access_control" "discovery" {
  name                              = "${local.issuer_host}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "oidc" {
  enabled = true
  aliases = [local.issuer_host]
  comment = "OIDC discovery documents for the k3s cluster"

  origin {
    domain_name              = aws_s3_bucket.discovery.bucket_regional_domain_name
    origin_id                = "discovery"
    origin_access_control_id = aws_cloudfront_origin_access_control.discovery.id
  }

  default_cache_behavior {
    target_origin_id       = "discovery"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    # AWS managed CachingOptimized
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.oidc.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

data "aws_iam_policy_document" "discovery_bucket" {
  statement {
    sid       = "AllowCloudFrontRead"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.discovery.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.oidc.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "discovery" {
  bucket = aws_s3_bucket.discovery.id
  policy = data.aws_iam_policy_document.discovery_bucket.json
}

resource "aws_route53_record" "oidc" {
  zone_id = aws_route53_zone.homelab.zone_id
  name    = local.issuer_host
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.oidc.domain_name
    zone_id                = aws_cloudfront_distribution.oidc.hosted_zone_id # CloudFront's fixed zone
    evaluate_target_health = false
  }
}
