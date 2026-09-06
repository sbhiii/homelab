# Reads the live TLS chain, so the distribution must be deployed and the DNS
# record resolving before this can be evaluated.
data "tls_certificate" "issuer" {
  url = local.issuer_url

  depends_on = [
    aws_cloudfront_distribution.oidc,
    aws_route53_record.oidc,
  ]
}

resource "aws_iam_openid_connect_provider" "cluster" {
  url             = local.issuer_url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.issuer.certificates[0].sha1_fingerprint]
}

data "aws_iam_policy_document" "cert_manager_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.cluster.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.issuer_host}:sub"
      values   = ["system:serviceaccount:${var.cert_manager_namespace}:${var.cert_manager_service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.issuer_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cert_manager" {
  name               = "cert-manager-route53"
  assume_role_policy = data.aws_iam_policy_document.cert_manager_trust.json
}

data "aws_iam_policy_document" "cert_manager_route53" {
  statement {
    sid       = "ChangeRecordsInHomelabZone"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/${data.aws_route53_zone.homelab.zone_id}"]
  }

  statement {
    # route53:GetChange cannot be scoped to a zone. This is an AWS API
    # limitation, not an oversight: change IDs are global.
    sid       = "PollChangeStatus"
    actions   = ["route53:GetChange"]
    resources = ["arn:aws:route53:::change/*"]
  }
}

resource "aws_iam_role_policy" "cert_manager_route53" {
  name   = "route53-dns01"
  role   = aws_iam_role.cert_manager.id
  policy = data.aws_iam_policy_document.cert_manager_route53.json
}
