data "tls_certificate" "issuer" {
  url = local.issuer_url
}

resource "aws_iam_openid_connect_provider" "cluster" {
  url             = local.issuer_url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.issuer.certificates[0].sha1_fingerprint]
}

data "aws_iam_policy_document" "external_secrets_trust" {
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
      values   = ["system:serviceaccount:${var.external_secrets_namespace}:${var.external_secrets_service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.issuer_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "external_secrets" {
  name               = "external-secrets-ssm-parameter-store"
  assume_role_policy = data.aws_iam_policy_document.external_secrets_trust.json
}

data "aws_iam_policy_document" "external_secrets_ssm" {
  statement {
    sid     = "ReadHomelabParameters"
    actions = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = [
      "arn:aws:ssm:${var.region}:${var.workload_account_id}:parameter/homelab/*"
    ]
  }

  statement {
    sid       = "ListHomelabParameters"
    actions   = ["ssm:GetParametersByPath"]
    resources = ["arn:aws:ssm:${var.region}:${var.workload_account_id}:parameter/homelab"]
  }
}

resource "aws_iam_role_policy" "external_secrets_ssm" {
  name   = "ssm-parameter-store"
  role   = aws_iam_role.external_secrets.id
  policy = data.aws_iam_policy_document.external_secrets_ssm.json
}

