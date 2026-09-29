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
  labels = {
    owner = "platform-team"
  }
}

output "buckets" {
  description = "Created buckets, keyed by their name in buckets.yaml."
  value       = module.gcs.buckets
}

output "iam_bindings" {
  description = "Authoritative role bindings created by the module."
  value       = module.gcs.iam_bindings
}

output "iam_members" {
  description = "Additive role grants created by the module."
  value       = module.gcs.iam_members
}
