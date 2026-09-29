# Helper for the live tests: reads the buckets and their IAM policies back
# from the API, independently of the module's own resources and state.

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.38.0, < 9.0.0"
    }
  }
}

variable "bucket_names" {
  description = "Bucket names to read, keyed by their name in the YAML file."
  type        = map(string)
}

data "google_storage_bucket" "this" {
  for_each = var.bucket_names
  name     = each.value
}

data "google_storage_bucket_iam_policy" "this" {
  for_each = var.bucket_names
  bucket   = each.value
}

output "buckets" {
  description = "Settings of each bucket as reported by the API."
  value = {
    for key, b in data.google_storage_bucket.this : key => {
      location                    = b.location
      storage_class               = b.storage_class
      versioning                  = try(b.versioning[0].enabled, false)
      uniform_bucket_level_access = b.uniform_bucket_level_access
      public_access_prevention    = b.public_access_prevention
      labels                      = b.labels
      lifecycle_rule_count        = length(b.lifecycle_rule)
      cors_count                  = length(b.cors)
      autoclass                   = try(b.autoclass[0].enabled, false)
      hierarchical_namespace      = try(b.hierarchical_namespace[0].enabled, false)
      soft_delete_seconds         = try(b.soft_delete_policy[0].retention_duration_seconds, null)
      website_main_page           = try(b.website[0].main_page_suffix, null)
      updated                     = b.updated
    }
  }
}

output "policies" {
  description = "IAM policy bindings of each bucket, keyed by role (plus condition title when there is one)."
  value = {
    for key, p in data.google_storage_bucket_iam_policy.this : key => {
      for binding in jsondecode(p.policy_data).bindings :
      "${binding.role}${try("|${binding.condition.title}", "")}" => sort(binding.members)
    }
  }
}

output "etags" {
  description = "IAM policy etag of each bucket."
  value       = { for key, p in data.google_storage_bucket_iam_policy.this : key => p.etag }
}
