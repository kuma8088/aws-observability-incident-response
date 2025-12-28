# S3 backend configuration
# Run `terraform init` with backend config:
# terraform init -backend-config="bucket=YOUR_STATE_BUCKET" \
#                -backend-config="key=observability/dev/terraform.tfstate"

terraform {
  backend "s3" {
    region         = "ap-northeast-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
