# Live tests against a real project: creates three buckets with IAM
# bindings, reads them back from the API, re-applies to prove there is no
# perpetual diff, then destroys everything.
#
#   terraform init -test-directory=tests/integration
#   terraform test -test-directory=tests/integration -var="project_id=MY_PROJECT"
#
# Needs credentials (gcloud auth application-default login) with permission to
# create and delete buckets and set their IAM policies (roles/storage.admin).

provider "google" {
  project = var.project_id
}

run "setup" {
  module {
    source = "./tests/integration/setup"
  }
}

run "create" {
  command = apply

  variables {
    config_file = "tests/integration/buckets.yaml"
    config_vars = {
      project_id    = var.project_id
      service_agent = run.setup.service_agent
      prefix        = "tfit-${run.setup.suffix}-"
    }
    name_prefix = "tfit-${run.setup.suffix}-"
    project_id  = var.project_id
  }

  assert {
    condition     = output.bucket_names["standard"] == "tfit-${run.setup.suffix}-standard"
    error_message = "Unexpected bucket name: ${output.bucket_names["standard"]}"
  }

  assert {
    condition     = output.bucket_urls["standard"] == "gs://tfit-${run.setup.suffix}-standard"
    error_message = "Unexpected bucket URL: ${output.bucket_urls["standard"]}"
  }

  assert {
    condition     = length(output.iam_bindings) == 2 && length(output.iam_members) == 2
    error_message = "Expected 2 authoritative bindings and 2 additive grants."
  }
}

run "verify" {
  module {
    source = "./tests/integration/verify"
  }

  variables {
    bucket_names = run.create.bucket_names
  }

  assert {
    condition = (
      output.buckets["standard"].location == "US-CENTRAL1" &&
      output.buckets["standard"].storage_class == "STANDARD" &&
      output.buckets["standard"].versioning == true &&
      output.buckets["standard"].uniform_bucket_level_access == true &&
      output.buckets["standard"].public_access_prevention == "enforced" &&
      output.buckets["standard"].lifecycle_rule_count == 3 &&
      output.buckets["standard"].cors_count == 1 &&
      output.buckets["standard"].soft_delete_seconds == 0
    )
    error_message = "The standard bucket does not match the YAML: ${jsonencode(output.buckets["standard"])}"
  }

  assert {
    condition     = output.buckets["standard"].labels["purpose"] == "terraform-module-test" && output.buckets["standard"].labels["tier"] == "standard"
    error_message = "Labels were not applied: ${jsonencode(output.buckets["standard"].labels)}"
  }

  assert {
    condition     = output.buckets["autoclass"].autoclass == true && output.buckets["autoclass"].website_main_page == "index.html"
    error_message = "Autoclass/website were not applied: ${jsonencode(output.buckets["autoclass"])}"
  }

  assert {
    condition     = output.buckets["hns"].hierarchical_namespace == true
    error_message = "Hierarchical namespace was not enabled."
  }

  assert {
    condition     = jsonencode(output.policies["standard"]["roles/storage.objectViewer"]) == jsonencode(["projectViewer:${var.project_id}"])
    error_message = "Authoritative binding missing: ${jsonencode(output.policies["standard"])}"
  }

  assert {
    condition     = jsonencode(output.policies["standard"]["roles/storage.objectCreator|tmp-prefix-only"]) == jsonencode(["serviceAccount:${run.setup.service_agent}"])
    error_message = "Conditional binding missing: ${jsonencode(output.policies["standard"])}"
  }

  assert {
    # Additive: the default member of the role stays next to the new one.
    condition     = contains(output.policies["standard"]["roles/storage.legacyBucketReader"], "projectEditor:${var.project_id}") && contains(output.policies["standard"]["roles/storage.legacyBucketReader"], "projectViewer:${var.project_id}")
    error_message = "Additive grant missing or default member removed: ${jsonencode(output.policies["standard"])}"
  }

  assert {
    condition     = contains(output.policies["hns"]["roles/storage.objectUser"], "serviceAccount:${run.setup.service_agent}")
    error_message = "Additive grant on the HNS bucket missing: ${jsonencode(output.policies["hns"])}"
  }
}

run "reapply_changes_nothing" {
  command = apply

  variables {
    config_file = "tests/integration/buckets.yaml"
    config_vars = {
      project_id    = var.project_id
      service_agent = run.setup.service_agent
      prefix        = "tfit-${run.setup.suffix}-"
    }
    name_prefix = "tfit-${run.setup.suffix}-"
    project_id  = var.project_id
  }

  # Any perpetual diff would update the bucket or its policy on this second
  # apply, changing the bucket's "updated" time or the policy etag.
  assert {
    condition     = alltrue([for key, b in google_storage_bucket.this : b.updated == run.verify.buckets[key].updated])
    error_message = "A bucket was modified by a second apply of the same configuration (perpetual diff)."
  }

  assert {
    condition = alltrue(concat(
      [for key, b in google_storage_bucket_iam_binding.this : b.etag == run.verify.etags[split("|", key)[0]]],
      [for key, m in google_storage_bucket_iam_member.this : m.etag == run.verify.etags[split("|", key)[0]]],
    ))
    error_message = "An IAM policy was modified by a second apply of the same configuration (perpetual diff)."
  }
}
