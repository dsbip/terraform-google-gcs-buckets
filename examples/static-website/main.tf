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

module "website" {
  source = "../.."

  config_file = "${path.module}/buckets.yaml"
  project_id  = var.project_id
}

output "site_url" {
  description = "Public URL of the site's index page."
  value       = "https://storage.googleapis.com/${module.website.bucket_names["example-site-www"]}/index.html"
}
