output "external_secrets_role_arn" {
  description = "Role the external-secrets ServiceAccount assumes."
  value       = aws_iam_role.external_secrets.arn
}
