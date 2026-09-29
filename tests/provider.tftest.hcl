# Plans every example with the real Google provider (not a mock), so the
# provider's own schema validation and plan-time logic run as well.
# Planning resources that don't exist yet makes no API calls, so a dummy
# access token is enough: no credentials needed, nothing is created.

provider "google" {
  project      = "my-project"
  access_token = "dummy-token-plans-make-no-api-calls"
}

run "basic" {
  command = plan

  variables {
    config_file = "examples/basic/buckets.yaml"
  }

  assert {
    condition     = length(google_storage_bucket.this) == 2 && length(google_storage_bucket_iam_binding.this) == 3
    error_message = "Unexpected resource counts."
  }
}

run "complete" {
  command = plan

  variables {
    config_file = "examples/complete/buckets.yaml"
    project_id  = "my-project"
  }

  assert {
    condition     = length(google_storage_bucket.this) == 7 && length(google_storage_bucket_iam_binding.this) == 7 && length(google_storage_bucket_iam_member.this) == 2
    error_message = "Unexpected resource counts."
  }
}

run "data_lake" {
  command = plan

  variables {
    config_file = "examples/data-lake/buckets.yaml"
  }

  assert {
    condition     = length(google_storage_bucket.this) == 5 && length(google_storage_bucket_iam_binding.this) == 14 && length(google_storage_bucket_iam_member.this) == 1
    error_message = "Unexpected resource counts: ${length(google_storage_bucket.this)} buckets, ${length(google_storage_bucket_iam_binding.this)} bindings, ${length(google_storage_bucket_iam_member.this)} members."
  }
}

run "static_website" {
  command = plan

  variables {
    config_file = "examples/static-website/buckets.yaml"
  }

  assert {
    condition     = length(google_storage_bucket.this) == 2 && length(google_storage_bucket_iam_binding.this) == 4
    error_message = "Unexpected resource counts."
  }
}

run "multi_environment" {
  command = plan

  variables {
    config_file = "examples/multi-environment/buckets.yaml"
    config_vars = {
      env        = "prod"
      project_id = "acme-prod-project"
      location   = "EU"
      teams      = ["analytics", "ml", "finance"]
    }
    name_prefix = "acme-prod-"
  }

  assert {
    condition     = length(google_storage_bucket.this) == 4 && length(google_storage_bucket_iam_binding.this) == 5
    error_message = "Unexpected resource counts."
  }
}
