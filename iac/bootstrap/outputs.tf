output "state_bucket_name" {
  description = "Bucket backing the terraform state for the other modules."
  value       = aws_s3_bucket.state.id
}
