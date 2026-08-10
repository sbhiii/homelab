# bootstrap

Creates the S3 bucket that `iac/aws` and `iac/hetzner` store their terraform
state in.

This module keeps **local state on purpose**. It cannot store its state in the
bucket it creates. It is applied once and then left alone; if its state file is
lost, `terraform import` the bucket rather than re-applying.

    terraform init
    terraform apply -var state_bucket_name=<globally-unique-name>
