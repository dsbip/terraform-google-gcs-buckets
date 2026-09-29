terraform {
  required_version = ">= 1.2.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.38.0, < 9.0.0"
    }
  }
}

variable "env" {
  description = "Environment name."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "The env must be dev or prod."
  }
}

variable "project_id" {
  description = "Project that owns the buckets of this environment."
  type        = string
}

variable "location" {
  description = "Location of every bucket."
  type        = string
  default     = "US-CENTRAL1"
}

variable "teams" {
  description = "Teams that get a scratch bucket."
  type        = list(string)
  default     = ["analytics", "ml"]
}

provider "google" {
  project = var.project_id
}

module "gcs" {
  source = "../.."

  config_file = "${path.module}/buckets.yaml"
  config_vars = {
    env        = var.env
    project_id = var.project_id
    location   = var.location
    teams      = var.teams
  }
  name_prefix = "acme-${var.env}-"
  project_id  = var.project_id
}

output "bucket_names" {
  description = "Bucket names (with the environment prefix), keyed by their name in buckets.yaml."
  value       = module.gcs.bucket_names
}
