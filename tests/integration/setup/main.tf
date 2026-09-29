# Helper for the live tests: a random suffix for globally unique bucket names
# and a service account that is guaranteed to exist in the project.

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.38.0, < 9.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0.0"
    }
  }
}

variable "project_id" {
  description = "Project the live tests run in."
  type        = string
}

resource "random_id" "suffix" {
  byte_length = 3
}

# The Cloud Storage service agent of the project; reading it creates it if
# needed, so it is always a valid IAM principal.
data "google_storage_project_service_account" "gcs" {
  project = var.project_id
}

output "suffix" {
  description = "Random hex suffix for bucket names."
  value       = random_id.suffix.hex
}

output "service_agent" {
  description = "Email of the project's Cloud Storage service agent."
  value       = data.google_storage_project_service_account.gcs.email_address
}
