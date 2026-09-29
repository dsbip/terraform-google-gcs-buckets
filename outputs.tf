output "buckets" {
  description = "Created buckets keyed by the name used in the YAML file."
  value = {
    for key, bucket in google_storage_bucket.this : key => {
      name          = bucket.name
      id            = bucket.id
      url           = bucket.url
      self_link     = bucket.self_link
      project       = bucket.project
      location      = bucket.location
      storage_class = bucket.storage_class
    }
  }

  # Every YAML error is reported here, in one message, before anything is
  # created: an invalid file makes module.config return no buckets at all.
  precondition {
    condition     = length(module.config.errors) == 0
    error_message = "Invalid bucket configuration in ${var.config_file}:\n  - ${join("\n  - ", module.config.errors)}"
  }
}

output "bucket_names" {
  description = "Actual bucket names (including name_prefix), keyed by the name used in the YAML file."
  value       = { for key, bucket in google_storage_bucket.this : key => bucket.name }
}

output "bucket_urls" {
  description = "gs:// URLs keyed by the name used in the YAML file."
  value       = { for key, bucket in google_storage_bucket.this : key => bucket.url }
}

output "iam_bindings" {
  description = "Authoritative role bindings, keyed by \"bucket|role[|condition title]\"."
  value = {
    for key, binding in google_storage_bucket_iam_binding.this : key => {
      bucket    = binding.bucket
      role      = binding.role
      members   = sort(tolist(binding.members))
      condition = one([for c in binding.condition : c.title])
    }
  }
}

output "iam_members" {
  description = "Additive role grants, keyed by \"bucket|role[|condition title]|member\"."
  value = {
    for key, grant in google_storage_bucket_iam_member.this : key => {
      bucket    = grant.bucket
      role      = grant.role
      member    = grant.member
      condition = one([for c in grant.condition : c.title])
    }
  }
}
