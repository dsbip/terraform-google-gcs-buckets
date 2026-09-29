module "config" {
  source = "./modules/config"

  # A missing file is reported by the config_file validation; skip reading it
  # so that validation error is the only one Terraform prints.
  yaml        = fileexists(var.config_file) ? templatefile(var.config_file, var.config_vars) : "buckets: []"
  project_id  = var.project_id
  name_prefix = var.name_prefix
  labels      = var.labels
}

# module.config returns empty maps when the YAML file has errors, so an
# invalid file plans no resources; the errors are raised by the precondition
# on output.buckets.
resource "google_storage_bucket" "this" {
  for_each = module.config.buckets

  name                        = each.value.name
  project                     = each.value.project_id
  location                    = each.value.location
  storage_class               = each.value.storage_class
  labels                      = each.value.labels
  force_destroy               = each.value.force_destroy
  deletion_policy             = each.value.deletion_policy
  uniform_bucket_level_access = each.value.uniform_bucket_level_access
  public_access_prevention    = each.value.public_access_prevention
  requester_pays              = each.value.requester_pays
  default_event_based_hold    = each.value.default_event_based_hold
  enable_object_retention     = each.value.enable_object_retention
  rpo                         = each.value.rpo

  dynamic "versioning" {
    for_each = each.value.versioning == null ? [] : [each.value.versioning]
    content {
      enabled = versioning.value
    }
  }

  dynamic "hierarchical_namespace" {
    for_each = each.value.hierarchical_namespace == null ? [] : [each.value.hierarchical_namespace]
    content {
      enabled = hierarchical_namespace.value
    }
  }

  dynamic "autoclass" {
    for_each = each.value.autoclass == null ? [] : [each.value.autoclass]
    content {
      enabled                = autoclass.value.enabled
      terminal_storage_class = autoclass.value.terminal_storage_class
    }
  }

  dynamic "soft_delete_policy" {
    for_each = each.value.soft_delete_retention_seconds == null ? [] : [each.value.soft_delete_retention_seconds]
    content {
      retention_duration_seconds = soft_delete_policy.value
    }
  }

  dynamic "encryption" {
    for_each = each.value.kms_key_name == null ? [] : [each.value.kms_key_name]
    content {
      default_kms_key_name = encryption.value
    }
  }

  dynamic "custom_placement_config" {
    for_each = each.value.data_locations == null ? [] : [each.value.data_locations]
    content {
      data_locations = custom_placement_config.value
    }
  }

  dynamic "retention_policy" {
    for_each = each.value.retention_policy == null ? [] : [each.value.retention_policy]
    content {
      retention_period = retention_policy.value.retention_period
      is_locked        = retention_policy.value.is_locked
    }
  }

  dynamic "logging" {
    for_each = each.value.logging == null ? [] : [each.value.logging]
    content {
      log_bucket        = logging.value.log_bucket
      log_object_prefix = logging.value.log_object_prefix
    }
  }

  dynamic "website" {
    for_each = each.value.website == null ? [] : [each.value.website]
    content {
      main_page_suffix = website.value.main_page_suffix
      not_found_page   = website.value.not_found_page
    }
  }

  dynamic "cors" {
    for_each = each.value.cors
    content {
      origin          = cors.value.origin
      method          = cors.value.method
      response_header = cors.value.response_header
      max_age_seconds = cors.value.max_age_seconds
    }
  }

  dynamic "lifecycle_rule" {
    for_each = each.value.lifecycle_rules
    content {
      action {
        type          = lifecycle_rule.value.action_type
        storage_class = lifecycle_rule.value.action_storage_class
      }
      condition {
        age                                     = lifecycle_rule.value.age
        created_before                          = lifecycle_rule.value.created_before
        custom_time_before                      = lifecycle_rule.value.custom_time_before
        days_since_custom_time                  = lifecycle_rule.value.days_since_custom_time
        days_since_noncurrent_time              = lifecycle_rule.value.days_since_noncurrent_time
        matches_prefix                          = lifecycle_rule.value.matches_prefix
        matches_storage_class                   = lifecycle_rule.value.matches_storage_class
        matches_suffix                          = lifecycle_rule.value.matches_suffix
        noncurrent_time_before                  = lifecycle_rule.value.noncurrent_time_before
        num_newer_versions                      = lifecycle_rule.value.num_newer_versions
        size_above_bytes                        = lifecycle_rule.value.size_above_bytes
        size_below_bytes                        = lifecycle_rule.value.size_below_bytes
        with_state                              = lifecycle_rule.value.with_state
        send_age_if_zero                        = lifecycle_rule.value.send_age_if_zero
        send_days_since_custom_time_if_zero     = lifecycle_rule.value.send_days_since_custom_time_if_zero
        send_days_since_noncurrent_time_if_zero = lifecycle_rule.value.send_days_since_noncurrent_time_if_zero
        send_num_newer_versions_if_zero         = lifecycle_rule.value.send_num_newer_versions_if_zero
      }
    }
  }
}

# Authoritative: Terraform owns the full member list of each role (per
# condition) on the bucket and removes members added outside this module.
resource "google_storage_bucket_iam_binding" "this" {
  for_each = module.config.iam_bindings

  bucket  = google_storage_bucket.this[each.value.bucket].name
  role    = each.value.role
  members = each.value.members

  dynamic "condition" {
    for_each = each.value.condition == null ? [] : [each.value.condition]
    content {
      title       = condition.value.title
      description = condition.value.description
      expression  = condition.value.expression
    }
  }
}

# Additive: grants a single member a role and leaves other members alone.
resource "google_storage_bucket_iam_member" "this" {
  for_each = module.config.iam_members

  bucket = google_storage_bucket.this[each.value.bucket].name
  role   = each.value.role
  member = each.value.member

  dynamic "condition" {
    for_each = each.value.condition == null ? [] : [each.value.condition]
    content {
      title       = condition.value.title
      description = condition.value.description
      expression  = condition.value.expression
    }
  }
}
