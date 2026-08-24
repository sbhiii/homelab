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

  statement {
    # Lets cert-manager resolve the zone from the record name, so the
    # ClusterIssuer does not have to name a zone ID and the gitops repository
    # stays free of AWS identifiers.
    #
    # The cost is real and is accepted deliberately: this action takes no
    # resource-level permissions, so it cannot be scoped to one zone. The role
    # can enumerate every hosted zone in the account. It grants no read of
    # record contents and no write, and this account holds one zone.
    sid       = "FindZoneByName"
    actions   = ["route53:ListHostedZonesByName"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "cert_manager_route53" {
  name   = "route53-dns01"
  role   = aws_iam_role.cert_manager.id
  policy = data.aws_iam_policy_document.cert_manager_route53.json
}
