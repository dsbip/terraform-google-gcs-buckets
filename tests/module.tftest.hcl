# Tests of the root module with a mocked Google provider: how the normalised
# configuration becomes resources, the outputs, and the plan-time failures
# for invalid input. No credentials or network access are needed.

mock_provider "google" {
  mock_resource "google_storage_bucket" {
    defaults = {
      url = "gs://mocked-bucket"
    }
  }
}

# --- Invalid input -----------------------------------------------------------------

run "invalid_configuration_fails_the_plan" {
  command = plan

  variables {
    config_file = "tests/fixtures/invalid.yaml"
  }

  # All YAML errors surface through the precondition on output.buckets.
  expect_failures = [output.buckets]
}

run "missing_config_file" {
  command = plan

  variables {
    config_file = "tests/fixtures/does-not-exist.yaml"
  }

  expect_failures = [var.config_file]
}

run "invalid_name_prefix" {
  command = plan

  variables {
    config_file = "tests/fixtures/minimal.yaml"
    name_prefix = "Team-"
  }

  expect_failures = [var.name_prefix]
}

run "invalid_labels_variable" {
  command = plan

  variables {
    config_file = "tests/fixtures/minimal.yaml"
    labels      = { Team = "Data Platform" }
  }

  expect_failures = [var.labels]
}

# --- Rendering ------------------------------------------------------------------

run "minimal_bucket" {
  command = plan

  variables {
    config_file = "tests/fixtures/minimal.yaml"
    labels      = { team = "platform" }
  }

  assert {
    condition     = length(google_storage_bucket.this) == 1 && length(google_storage_bucket_iam_binding.this) == 0 && length(google_storage_bucket_iam_member.this) == 0
    error_message = "Expected exactly one bucket and no IAM resources."
  }

  assert {
    condition = (
      google_storage_bucket.this["fixture-minimal"].name == "fixture-minimal" &&
      google_storage_bucket.this["fixture-minimal"].location == "US-CENTRAL1" &&
      google_storage_bucket.this["fixture-minimal"].storage_class == "STANDARD" &&
      google_storage_bucket.this["fixture-minimal"].uniform_bucket_level_access == true &&
      google_storage_bucket.this["fixture-minimal"].public_access_prevention == "enforced" &&
      google_storage_bucket.this["fixture-minimal"].force_destroy == false &&
      google_storage_bucket.this["fixture-minimal"].versioning[0].enabled == false
    )
    error_message = "The module's secure defaults should be rendered."
  }

  assert {
    condition     = google_storage_bucket.this["fixture-minimal"].labels == tomap({ team = "platform" })
    error_message = "var.labels should apply to every bucket."
  }

  assert {
    # Blocks that are not configured must not be rendered at all.
    condition = alltrue([
      length(google_storage_bucket.this["fixture-minimal"].autoclass) == 0,
      length(google_storage_bucket.this["fixture-minimal"].encryption) == 0,
      length(google_storage_bucket.this["fixture-minimal"].logging) == 0,
      length(google_storage_bucket.this["fixture-minimal"].retention_policy) == 0,
      length(google_storage_bucket.this["fixture-minimal"].custom_placement_config) == 0,
      length(google_storage_bucket.this["fixture-minimal"].hierarchical_namespace) == 0,
      length(google_storage_bucket.this["fixture-minimal"].cors) == 0,
      length(google_storage_bucket.this["fixture-minimal"].lifecycle_rule) == 0,
    ])
    error_message = "Unset optional blocks should be omitted."
  }

  assert {
    condition = (
      google_storage_bucket.this["fixture-minimal"].requester_pays == null &&
      google_storage_bucket.this["fixture-minimal"].default_event_based_hold == null &&
      google_storage_bucket.this["fixture-minimal"].enable_object_retention == null
    )
    error_message = "Unset optional arguments should be left to the provider."
  }
}

run "lifecycle_rules" {
  command = plan

  variables {
    config_file = "tests/fixtures/lifecycle.yaml"
  }

  assert {
    condition     = length(google_storage_bucket.this["fixture-lifecycle"].lifecycle_rule) == 3
    error_message = "Expected 3 lifecycle rules."
  }

  assert {
    condition = (
      one(google_storage_bucket.this["fixture-lifecycle"].lifecycle_rule[0].action).type == "SetStorageClass" &&
      one(google_storage_bucket.this["fixture-lifecycle"].lifecycle_rule[0].action).storage_class == "NEARLINE" &&
      one(google_storage_bucket.this["fixture-lifecycle"].lifecycle_rule[0].condition).age == 30 &&
      one(google_storage_bucket.this["fixture-lifecycle"].lifecycle_rule[0].condition).with_state == "LIVE" &&
      one(google_storage_bucket.this["fixture-lifecycle"].lifecycle_rule[0].condition).matches_storage_class == tolist(["STANDARD"]) &&
      one(google_storage_bucket.this["fixture-lifecycle"].lifecycle_rule[0].condition).send_age_if_zero == false
    )
    error_message = "Rule 0 is rendered incorrectly."
  }

  assert {
    condition = (
      one(google_storage_bucket.this["fixture-lifecycle"].lifecycle_rule[1].condition).age == 0 &&
      one(google_storage_bucket.this["fixture-lifecycle"].lifecycle_rule[1].condition).send_age_if_zero == true &&
      one(google_storage_bucket.this["fixture-lifecycle"].lifecycle_rule[1].condition).send_num_newer_versions_if_zero == true &&
      one(google_storage_bucket.this["fixture-lifecycle"].lifecycle_rule[1].condition).send_days_since_noncurrent_time_if_zero == true &&
      one(google_storage_bucket.this["fixture-lifecycle"].lifecycle_rule[1].condition).send_days_since_custom_time_if_zero == true &&
      one(google_storage_bucket.this["fixture-lifecycle"].lifecycle_rule[1].condition).created_before == "2024-01-01"
    )
    error_message = "Zero-valued criteria must be sent and dates normalised."
  }

  assert {
    condition = (
      one(google_storage_bucket.this["fixture-lifecycle"].lifecycle_rule[2].condition).size_above_bytes == 1073741824 &&
      one(google_storage_bucket.this["fixture-lifecycle"].lifecycle_rule[2].condition).matches_prefix == tolist(["tmp/"]) &&
      one(google_storage_bucket.this["fixture-lifecycle"].lifecycle_rule[2].condition).age == null
    )
    error_message = "Rule 2 is rendered incorrectly."
  }
}

# --- Stable addresses --------------------------------------------------------------

run "order_a" {
  command = plan

  variables {
    config_file = "tests/fixtures/order-a.yaml"
  }

  assert {
    condition     = jsonencode(sort(keys(google_storage_bucket.this))) == jsonencode(["fixture-first", "fixture-second"])
    error_message = "Buckets are keyed by name."
  }

  assert {
    condition     = jsonencode(sort(keys(google_storage_bucket_iam_binding.this))) == jsonencode(["fixture-first|roles/storage.objectViewer", "fixture-second|roles/storage.objectCreator"])
    error_message = "Bindings are keyed by bucket and role."
  }

  assert {
    condition     = jsonencode(sort(keys(google_storage_bucket_iam_member.this))) == jsonencode(["fixture-first|roles/storage.objectAdmin|user:admin@example.com", "fixture-first|roles/storage.objectAdmin|user:backup@example.com"])
    error_message = "Additive grants are keyed by bucket, role and member."
  }
}

run "order_b" {
  command = plan

  # The same document with buckets, bindings and members reordered must
  # produce exactly the same resource addresses (no churn on reordering).
  variables {
    config_file = "tests/fixtures/order-b.yaml"
  }

  assert {
    condition     = jsonencode(sort(keys(google_storage_bucket.this))) == jsonencode(["fixture-first", "fixture-second"])
    error_message = "Buckets are keyed by name."
  }

  assert {
    condition     = jsonencode(sort(keys(google_storage_bucket_iam_binding.this))) == jsonencode(["fixture-first|roles/storage.objectViewer", "fixture-second|roles/storage.objectCreator"])
    error_message = "Bindings are keyed by bucket and role."
  }

  assert {
    condition     = jsonencode(sort(keys(google_storage_bucket_iam_member.this))) == jsonencode(["fixture-first|roles/storage.objectAdmin|user:admin@example.com", "fixture-first|roles/storage.objectAdmin|user:backup@example.com"])
    error_message = "Additive grants are keyed by bucket, role and member."
  }
}

# --- Outputs (mocked apply) --------------------------------------------------------

run "outputs_after_apply" {
  command = apply

  variables {
    config_file = "tests/fixtures/order-a.yaml"
    name_prefix = "acme-"
    project_id  = "my-project"
  }

  assert {
    condition     = jsonencode(output.bucket_names) == jsonencode({ fixture-first = "acme-fixture-first", fixture-second = "acme-fixture-second" })
    error_message = "Unexpected bucket_names: ${jsonencode(output.bucket_names)}"
  }

  assert {
    condition = (
      output.buckets["fixture-first"].name == "acme-fixture-first" &&
      output.buckets["fixture-first"].project == "my-project" &&
      output.buckets["fixture-first"].location == "US" &&
      output.buckets["fixture-first"].storage_class == "STANDARD" &&
      output.buckets["fixture-first"].url == "gs://mocked-bucket"
    )
    error_message = "Unexpected buckets output: ${jsonencode(output.buckets)}"
  }

  assert {
    condition     = jsonencode(sort(keys(output.bucket_urls))) == jsonencode(["fixture-first", "fixture-second"])
    error_message = "bucket_urls should be keyed by the YAML names."
  }

  assert {
    condition = jsonencode(output.iam_bindings) == jsonencode({
      "fixture-first|roles/storage.objectViewer" = {
        bucket    = "acme-fixture-first"
        role      = "roles/storage.objectViewer"
        members   = ["group:readers@example.com"]
        condition = null
      }
      "fixture-second|roles/storage.objectCreator" = {
        bucket    = "acme-fixture-second"
        role      = "roles/storage.objectCreator"
        members   = ["serviceAccount:writer@my-project.iam.gserviceaccount.com"]
        condition = null
      }
    })
    error_message = "Unexpected iam_bindings: ${jsonencode(output.iam_bindings)}"
  }

  assert {
    condition     = output.iam_members["fixture-first|roles/storage.objectAdmin|user:admin@example.com"].bucket == "acme-fixture-first" && output.iam_members["fixture-first|roles/storage.objectAdmin|user:admin@example.com"].member == "user:admin@example.com"
    error_message = "Unexpected iam_members: ${jsonencode(output.iam_members)}"
  }
}
