# Every example YAML file must be valid and plan the expected resources.
# The Google provider is mocked, so no credentials or network access are
# needed.

mock_provider "google" {}

run "basic" {
  command = plan

  variables {
    config_file = "examples/basic/buckets.yaml"
    project_id  = "my-project"
  }

  assert {
    condition     = length(google_storage_bucket.this) == 2
    error_message = "Expected 2 buckets."
  }

  assert {
    condition     = google_storage_bucket.this["example-basic-uploads"].location == "US-CENTRAL1" && google_storage_bucket.this["example-basic-exports"].location == "US-CENTRAL1"
    error_message = "Both buckets should inherit the location from defaults."
  }

  assert {
    condition     = google_storage_bucket.this["example-basic-uploads"].versioning[0].enabled == true && google_storage_bucket.this["example-basic-exports"].versioning[0].enabled == false
    error_message = "Versioning should be on for uploads only."
  }

  assert {
    condition     = google_storage_bucket.this["example-basic-exports"].storage_class == "NEARLINE" && google_storage_bucket.this["example-basic-uploads"].storage_class == "STANDARD"
    error_message = "Unexpected storage classes."
  }

  assert {
    condition     = google_storage_bucket.this["example-basic-uploads"].uniform_bucket_level_access == true && google_storage_bucket.this["example-basic-uploads"].public_access_prevention == "enforced"
    error_message = "Secure defaults should apply."
  }

  assert {
    condition     = one(google_storage_bucket.this["example-basic-exports"].lifecycle_rule[0].condition).age == 30 && one(google_storage_bucket.this["example-basic-exports"].lifecycle_rule[0].action).type == "Delete"
    error_message = "The exports bucket should delete objects after 30 days."
  }

  assert {
    condition = jsonencode(sort(keys(google_storage_bucket_iam_binding.this))) == jsonencode([
      "example-basic-exports|roles/storage.objectUser",
      "example-basic-uploads|roles/storage.objectCreator",
      "example-basic-uploads|roles/storage.objectViewer",
    ])
    error_message = "Unexpected authoritative bindings: ${jsonencode(keys(google_storage_bucket_iam_binding.this))}"
  }

  assert {
    condition     = google_storage_bucket_iam_binding.this["example-basic-uploads|roles/storage.objectViewer"].members == toset(["group:app-readers@example.com"])
    error_message = "The groups shorthand should add the group: prefix."
  }

  assert {
    condition     = length(google_storage_bucket_iam_member.this) == 0
    error_message = "The basic example has no additive grants."
  }
}

run "complete" {
  command = plan

  variables {
    config_file = "examples/complete/buckets.yaml"
    project_id  = "my-project"
    labels      = { owner = "platform-team" }
  }

  assert {
    condition = jsonencode(sort(keys(google_storage_bucket.this))) == jsonencode([
      "example-complete-compliance",
      "example-complete-data",
      "example-complete-dual-region",
      "example-complete-hns",
      "example-complete-logs",
      "example-complete-public-datasets",
      "example-complete-site",
    ])
    error_message = "Unexpected buckets: ${jsonencode(keys(google_storage_bucket.this))}"
  }

  # --- data bucket ------------------------------------------------------------
  assert {
    condition     = google_storage_bucket.this["example-complete-data"].location == "US-CENTRAL1" && google_storage_bucket.this["example-complete-data"].project == "my-project"
    error_message = "The data bucket should override the default location."
  }

  assert {
    condition = google_storage_bucket.this["example-complete-data"].labels == tomap({
      owner               = "platform-team"
      managed-by          = "terraform"
      cost-center         = "cc-1234"
      data-classification = "confidential"
    })
    error_message = "Labels should merge var.labels, defaults and bucket labels: ${jsonencode(google_storage_bucket.this["example-complete-data"].labels)}"
  }

  assert {
    condition     = google_storage_bucket.this["example-complete-data"].encryption[0].default_kms_key_name == "projects/my-project/locations/us-central1/keyRings/storage/cryptoKeys/gcs-data"
    error_message = "The KMS key should be set."
  }

  assert {
    condition     = google_storage_bucket.this["example-complete-data"].retention_policy[0].retention_period == "86400" && google_storage_bucket.this["example-complete-data"].retention_policy[0].is_locked == false
    error_message = "The retention policy should be set and unlocked."
  }

  assert {
    condition     = google_storage_bucket.this["example-complete-data"].logging[0].log_bucket == "example-complete-logs" && google_storage_bucket.this["example-complete-data"].logging[0].log_object_prefix == "data/"
    error_message = "Access logging should be configured."
  }

  assert {
    condition     = google_storage_bucket.this["example-complete-data"].deletion_policy == "PREVENT" && google_storage_bucket.this["example-complete-data"].force_destroy == false
    error_message = "The data bucket should be protected from deletion."
  }

  assert {
    condition     = length(google_storage_bucket.this["example-complete-data"].lifecycle_rule) == 6
    error_message = "The data bucket should have its own 6 lifecycle rules."
  }

  assert {
    condition     = one(google_storage_bucket.this["example-complete-data"].lifecycle_rule[5].condition).age == 0 && one(google_storage_bucket.this["example-complete-data"].lifecycle_rule[5].condition).send_age_if_zero == true
    error_message = "age: 0 must be sent to the API."
  }

  assert {
    condition     = one(google_storage_bucket.this["example-complete-data"].lifecycle_rule[1].condition).send_age_if_zero == false
    error_message = "send_age_if_zero should only be set for age: 0."
  }

  # --- other buckets -----------------------------------------------------------
  assert {
    condition     = google_storage_bucket.this["example-complete-logs"].autoclass[0].enabled == true && google_storage_bucket.this["example-complete-logs"].autoclass[0].terminal_storage_class == "ARCHIVE"
    error_message = "Autoclass should be enabled on the logs bucket."
  }

  assert {
    condition     = length(google_storage_bucket.this["example-complete-logs"].lifecycle_rule) == 1 && one(google_storage_bucket.this["example-complete-logs"].lifecycle_rule[0].action).type == "AbortIncompleteMultipartUpload"
    error_message = "The logs bucket should inherit the default lifecycle rule."
  }

  assert {
    condition     = google_storage_bucket.this["example-complete-site"].public_access_prevention == "inherited" && google_storage_bucket.this["example-complete-site"].website[0].main_page_suffix == "index.html" && google_storage_bucket.this["example-complete-site"].website[0].not_found_page == "404.html"
    error_message = "The site bucket should be a public website."
  }

  assert {
    condition     = google_storage_bucket.this["example-complete-site"].cors[0].origin == tolist(["https://www.example.com"]) && google_storage_bucket.this["example-complete-site"].cors[0].method == tolist(["GET", "HEAD"]) && google_storage_bucket.this["example-complete-site"].cors[0].max_age_seconds == 3600
    error_message = "CORS should be configured on the site bucket."
  }

  assert {
    condition     = google_storage_bucket.this["example-complete-public-datasets"].requester_pays == true
    error_message = "Requester pays should be enabled."
  }

  assert {
    condition     = google_storage_bucket.this["example-complete-dual-region"].custom_placement_config[0].data_locations == toset(["US-EAST1", "US-WEST1"]) && google_storage_bucket.this["example-complete-dual-region"].rpo == "ASYNC_TURBO"
    error_message = "The dual-region bucket should use turbo replication."
  }

  assert {
    condition     = google_storage_bucket.this["example-complete-hns"].hierarchical_namespace[0].enabled == true && google_storage_bucket.this["example-complete-hns"].soft_delete_policy[0].retention_duration_seconds == 0
    error_message = "The HNS bucket should have HNS on and soft delete off."
  }

  assert {
    condition     = google_storage_bucket.this["example-complete-data"].soft_delete_policy[0].retention_duration_seconds == 604800
    error_message = "Soft delete retention should be inherited from defaults."
  }

  assert {
    condition     = google_storage_bucket.this["example-complete-compliance"].storage_class == "ARCHIVE" && google_storage_bucket.this["example-complete-compliance"].enable_object_retention == true && google_storage_bucket.this["example-complete-compliance"].default_event_based_hold == true
    error_message = "The compliance bucket settings are wrong."
  }

  assert {
    condition     = length(google_storage_bucket.this["example-complete-compliance"].lifecycle_rule) == 0
    error_message = "lifecycle_rules: [] should override the default rules."
  }

  # --- IAM -------------------------------------------------------------------
  assert {
    condition = google_storage_bucket_iam_binding.this["example-complete-data|roles/storage.objectViewer"].members == toset([
      "domain:example.com",
      "group:data-readers@example.com",
      "principalSet://iam.googleapis.com/projects/123456789012/locations/global/workloadIdentityPools/github/attribute.repository/example-org/data-pipelines",
      "projectViewer:my-project",
      "serviceAccount:reporting@my-project.iam.gserviceaccount.com",
      "user:alice@example.com",
    ])
    error_message = "Every principal kind should be passed through: ${jsonencode(google_storage_bucket_iam_binding.this["example-complete-data|roles/storage.objectViewer"].members)}"
  }

  assert {
    condition = google_storage_bucket_iam_binding.this["example-complete-data|roles/storage.objectUser"].members == toset([
      "group:data-engineers@example.com",
      "serviceAccount:etl@my-project.iam.gserviceaccount.com",
      "user:bob@example.com",
    ])
    error_message = "Shorthand lists should get their prefixes."
  }

  assert {
    condition     = google_storage_bucket_iam_binding.this["example-complete-data|roles/storage.objectViewer|expires-2027"].condition[0].expression == "request.time < timestamp(\"2027-01-01T00:00:00Z\")"
    error_message = "The conditional binding should carry its condition."
  }

  assert {
    condition = jsonencode(sort(keys(google_storage_bucket_iam_member.this))) == jsonencode([
      "example-complete-data|roles/storage.legacyBucketReader|principal://iam.googleapis.com/projects/123456789012/locations/global/workloadIdentityPools/my-project.svc.id.goog/subject/ns/analytics/sa/reader",
      "example-complete-data|roles/storage.objectCreator|incoming-prefix-only|serviceAccount:ingest@my-project.iam.gserviceaccount.com",
    ])
    error_message = "Unexpected additive grants: ${jsonencode(keys(google_storage_bucket_iam_member.this))}"
  }

  assert {
    condition     = google_storage_bucket_iam_binding.this["example-complete-site|roles/storage.objectViewer"].members == toset(["allUsers"]) && google_storage_bucket_iam_binding.this["example-complete-public-datasets|roles/storage.objectViewer"].members == toset(["allAuthenticatedUsers"])
    error_message = "Public principals should be granted on the public buckets."
  }

  assert {
    condition     = google_storage_bucket_iam_binding.this["example-complete-data|roles/storage.objectViewer"].bucket == "example-complete-data"
    error_message = "Bindings should target the bucket by its name."
  }

  assert {
    condition     = length(google_storage_bucket_iam_binding.this) == 7
    error_message = "Expected 7 authoritative bindings, got ${length(google_storage_bucket_iam_binding.this)}."
  }
}

run "data_lake" {
  command = plan

  variables {
    config_file = "examples/data-lake/buckets.yaml"
    project_id  = "my-data-project"
  }

  assert {
    condition     = length(google_storage_bucket.this) == 5
    error_message = "Expected 5 buckets."
  }

  assert {
    condition = alltrue([
      for name in ["example-lake-landing", "example-lake-bronze", "example-lake-silver", "example-lake-gold", "example-lake-archive"] :
      google_storage_bucket_iam_binding.this["${name}|roles/storage.admin"].members == toset(["group:gcp-platform-admins@example.com"])
    ])
    error_message = "The platform-admins anchor should be expanded on every bucket."
  }

  assert {
    condition     = length(google_storage_bucket.this["example-lake-bronze"].lifecycle_rule) == 2 && length(google_storage_bucket.this["example-lake-silver"].lifecycle_rule) == 2 && length(google_storage_bucket.this["example-lake-gold"].lifecycle_rule) == 2
    error_message = "Layers without their own rules should inherit the 2 default rules."
  }

  assert {
    condition     = length(google_storage_bucket.this["example-lake-landing"].lifecycle_rule) == 2 && one(google_storage_bucket.this["example-lake-landing"].lifecycle_rule[0].condition).age == 7
    error_message = "The landing bucket should use its own rules."
  }

  assert {
    condition     = google_storage_bucket.this["example-lake-landing"].versioning[0].enabled == false && google_storage_bucket.this["example-lake-bronze"].versioning[0].enabled == true
    error_message = "Versioning default should be overridable."
  }

  assert {
    condition     = google_storage_bucket.this["example-lake-bronze"].retention_policy[0].retention_period == "2592000"
    error_message = "Bronze should have a 30-day retention policy."
  }

  assert {
    condition     = google_storage_bucket.this["example-lake-gold"].labels["layer"] == "gold" && google_storage_bucket.this["example-lake-gold"].labels["domain"] == "data-lake"
    error_message = "Bucket labels should merge with default labels."
  }

  assert {
    condition     = google_storage_bucket_iam_binding.this["example-lake-gold|roles/storage.objectViewer"].members == toset(["domain:partner.example.org", "group:analysts@example.com", "group:data-engineers@example.com"])
    error_message = "The gold readers binding is wrong."
  }

  assert {
    condition     = google_storage_bucket_iam_member.this["example-lake-gold|roles/storage.objectViewer|reports-prefix|serviceAccount:looker@bi-project.iam.gserviceaccount.com"].condition[0].title == "reports-prefix"
    error_message = "The additive conditional grant is missing."
  }

  assert {
    condition     = one(google_storage_bucket.this["example-lake-archive"].lifecycle_rule[1].action).storage_class == "ARCHIVE"
    error_message = "The archive bucket should tier down to ARCHIVE."
  }
}

run "static_website" {
  command = plan

  variables {
    config_file = "examples/static-website/buckets.yaml"
    project_id  = "my-project"
  }

  assert {
    condition     = length(google_storage_bucket.this) == 2
    error_message = "Expected 2 buckets."
  }

  assert {
    condition     = google_storage_bucket_iam_binding.this["example-site-www|roles/storage.objectViewer"].members == toset(["allUsers"])
    error_message = "The site should be publicly readable."
  }

  assert {
    condition     = google_storage_bucket.this["example-site-www"].public_access_prevention == "inherited" && google_storage_bucket.this["example-site-artifacts"].public_access_prevention == "enforced"
    error_message = "Only the website bucket should allow public access."
  }

  assert {
    condition     = google_storage_bucket.this["example-site-www"].cors[0].method == tolist(["GET", "HEAD", "OPTIONS"])
    error_message = "CORS methods are wrong."
  }
}

run "multi_environment_dev" {
  command = plan

  variables {
    config_file = "examples/multi-environment/buckets.yaml"
    config_vars = {
      env        = "dev"
      project_id = "acme-dev-project"
      location   = "US-CENTRAL1"
      teams      = ["analytics", "ml"]
    }
    name_prefix = "acme-dev-"
    project_id  = "acme-dev-project"
  }

  assert {
    condition     = jsonencode(sort([for b in google_storage_bucket.this : b.name])) == jsonencode(["acme-dev-analytics-scratch", "acme-dev-app-data", "acme-dev-ml-scratch"])
    error_message = "Unexpected bucket names: ${jsonencode([for b in google_storage_bucket.this : b.name])}"
  }

  assert {
    condition     = google_storage_bucket.this["app-data"].versioning[0].enabled == false && google_storage_bucket.this["app-data"].force_destroy == true && google_storage_bucket.this["app-data"].deletion_policy == "DELETE"
    error_message = "Dev buckets should be disposable."
  }

  assert {
    condition     = length(google_storage_bucket.this["app-data"].retention_policy) == 0
    error_message = "Dev should not get a retention policy."
  }

  assert {
    condition     = one(google_storage_bucket.this["ml-scratch"].lifecycle_rule[0].condition).age == 7
    error_message = "Dev scratch buckets should expire objects after 7 days."
  }

  assert {
    condition     = google_storage_bucket_iam_binding.this["app-data|roles/storage.objectUser"].members == toset(["serviceAccount:app@acme-dev-project.iam.gserviceaccount.com"])
    error_message = "The project ID should be templated into the service account."
  }

  assert {
    condition     = google_storage_bucket_iam_binding.this["app-data|roles/storage.objectUser"].bucket == "acme-dev-app-data"
    error_message = "Bindings should target the prefixed bucket name."
  }
}

run "multi_environment_prod" {
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
    project_id  = "acme-prod-project"
  }

  assert {
    condition     = length(google_storage_bucket.this) == 4 && google_storage_bucket.this["finance-scratch"].name == "acme-prod-finance-scratch"
    error_message = "Prod should get a scratch bucket per team."
  }

  assert {
    condition     = google_storage_bucket.this["app-data"].versioning[0].enabled == true && google_storage_bucket.this["app-data"].force_destroy == false && google_storage_bucket.this["app-data"].deletion_policy == "PREVENT"
    error_message = "Prod buckets should be protected."
  }

  assert {
    condition     = google_storage_bucket.this["app-data"].retention_policy[0].retention_period == "604800" && google_storage_bucket.this["app-data"].location == "EU"
    error_message = "Prod should get a retention policy in the EU."
  }

  assert {
    condition     = one(google_storage_bucket.this["ml-scratch"].lifecycle_rule[0].condition).age == 30
    error_message = "Prod scratch buckets should keep objects for 30 days."
  }

  assert {
    condition     = google_storage_bucket.this["app-data"].labels["env"] == "prod"
    error_message = "The env label should be templated."
  }
}
