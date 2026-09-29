terraform {
  required_version = ">= 1.2.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.38.0, < 9.0.0"
    }
  }
}

variable "project_id" {
  description = "Project that owns the buckets."
  type        = string
}

provider "google" {
  project = var.project_id
}

module "gcs" {
  source = "../.."

  config_file = "${path.module}/buckets.yaml"
  project_id  = var.project_id
}

output "bucket_urls" {
  description = "gs:// URL of each bucket, keyed by its name in buckets.yaml."
  value       = module.gcs.bucket_urls
}
