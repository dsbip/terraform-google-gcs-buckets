# Unit tests for modules/config: every validation rule, with the exact error
# messages users see. Each run plans the configuration module on its own; an
# invalid document never fails the plan here, it only fills output.errors
# (the root module turns a non-empty list into a plan error).

# --- Document structure --------------------------------------------------------

run "empty_document" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = "  \n"
  }
  assert {
    condition     = jsonencode(output.errors) == jsonencode(["the configuration is empty; expected a mapping with a 'buckets' list"])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
  assert {
    condition     = length(output.buckets) == 0 && length(output.iam_bindings) == 0 && length(output.iam_members) == 0
    error_message = "Nothing should be produced for an invalid document."
  }
}

run "document_separator_only" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = "---\n"
  }
  assert {
    condition     = jsonencode(output.errors) == jsonencode(["the configuration is empty; expected a mapping with a 'buckets' list"])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "document_not_a_mapping" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = <<-EOT
      - name: bucket-a
        location: US
    EOT
  }
  assert {
    condition     = jsonencode(output.errors) == jsonencode(["the configuration must be a mapping with a 'buckets' list"])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "missing_buckets_key" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = <<-EOT
      defaults:
        location: US
    EOT
  }
  assert {
    condition     = jsonencode(output.errors) == jsonencode(["missing required top-level key 'buckets'"])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "buckets_not_a_list" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = <<-EOT
      buckets:
        name: a
        location: US
    EOT
  }
  assert {
    condition     = jsonencode(output.errors) == jsonencode(["'buckets' must be a list of bucket definitions"])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "defaults_not_a_mapping" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = <<-EOT
      defaults: [US]
      buckets: []
    EOT
  }
  assert {
    condition     = jsonencode(output.errors) == jsonencode(["'defaults' must be a mapping of bucket attributes"])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "unknown_top_level_keys" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = <<-EOT
      bucket:
        - name: bucket-a
      settings: {}
      x-allowed: ignored
      buckets: []
    EOT
  }
  assert {
    condition     = jsonencode(output.errors) == jsonencode(["unknown top-level key(s): bucket, settings (allowed: buckets, defaults and x-* extension keys)"])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

# --- Bucket entries and names ----------------------------------------------------

run "bucket_not_a_mapping" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = <<-EOT
      buckets:
        - just-a-name
    EOT
  }
  assert {
    condition     = jsonencode(output.errors) == jsonencode(["buckets[0]: must be a mapping of bucket attributes"])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "missing_or_invalid_name" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = <<-EOT
      defaults:
        location: US
      buckets:
        - storage_class: STANDARD
        - name: [a, b]
        - name: ~
    EOT
  }
  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "buckets[0]: 'name' is required",
      "buckets[1]: name must be a string, got [\"a\",\"b\"]",
      "buckets[2]: 'name' is required",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "invalid_bucket_names" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = <<-EOT
      defaults:
        location: US
      buckets:
        - name: Uppercase
        - name: ab
        - name: a-very-long-bucket-name-that-goes-well-beyond-the-sixty-three-limit
        - name: 192.168.5.4
        - name: googbucket
        - name: my-g00gle-bucket
        - name: example.a-component-that-is-definitely-longer-than-sixty-three-characters-long.com
        - name: -dash-start
        - name: double..dot
        - name: under_score_
    EOT
  }
  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "bucket \"-dash-start\": name \"-dash-start\" may only contain lowercase letters, digits, dashes, underscores and dots, and must start and end with a letter or digit",
      "bucket \"192.168.5.4\": name \"192.168.5.4\" cannot be an IP address",
      "bucket \"Uppercase\": name \"Uppercase\" may only contain lowercase letters, digits, dashes, underscores and dots, and must start and end with a letter or digit",
      "bucket \"a-very-long-bucket-name-that-goes-well-beyond-the-sixty-three-limit\": name \"a-very-long-bucket-name-that-goes-well-beyond-the-sixty-three-limit\" must be 3-63 characters long (up to 222 if it contains dots)",
      "bucket \"ab\": name \"ab\" must be 3-63 characters long (up to 222 if it contains dots)",
      "bucket \"double..dot\": name \"double..dot\" has an empty dot-separated part or one longer than 63 characters",
      "bucket \"example.a-component-that-is-definitely-longer-than-sixty-three-characters-long.com\": name \"example.a-component-that-is-definitely-longer-than-sixty-three-characters-long.com\" has an empty dot-separated part or one longer than 63 characters",
      "bucket \"googbucket\": name \"googbucket\" cannot start with \"goog\"",
      "bucket \"my-g00gle-bucket\": name \"my-g00gle-bucket\" cannot contain \"google\" or a close misspelling of it",
      "bucket \"under_score_\": name \"under_score_\" may only contain lowercase letters, digits, dashes, underscores and dots, and must start and end with a letter or digit",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "name_prefix_is_validated_with_the_name" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    name_prefix = "team-with-a-rather-long-prefix-"
    yaml        = <<-EOT
      buckets:
        - name: and-a-much-longer-bucket-name-here
          location: US
    EOT
  }
  assert {
    condition     = jsonencode(output.errors) == jsonencode(["bucket \"and-a-much-longer-bucket-name-here\": name \"team-with-a-rather-long-prefix-and-a-much-longer-bucket-name-here\" must be 3-63 characters long (up to 222 if it contains dots)"])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "duplicate_names" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = <<-EOT
      defaults:
        location: US
      buckets:
        - name: dup
          iam:
            - role: roles/storage.objectViewer
              members: [user:a@example.com]
        - name: unique
        - name: dup
          iam:
            - role: roles/storage.objectViewer
              members: [user:b@example.com]
    EOT
  }
  assert {
    # The IAM entries of the two "dup" buckets must not be reported as
    # duplicates of each other.
    condition     = jsonencode(output.errors) == jsonencode(["bucket \"dup\": defined more than once (buckets[0], buckets[2])"])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

# --- Attributes ------------------------------------------------------------------

run "unknown_attributes" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = <<-EOT
      defaults:
        location: US
        name: shared
        iam: []
        colour: blue
      buckets:
        - name: bucket-a
          storage_clas: NEARLINE
          versionning: true
    EOT
  }
  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "bucket \"bucket-a\": unknown attribute(s): storage_clas, versionning",
      "defaults: iam can only be set on individual buckets",
      "defaults: name can only be set on individual buckets",
      "defaults: unknown attribute(s): colour",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "missing_location" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = <<-EOT
      buckets:
        - name: bucket-a
        - name: bucket-b
          location: ~
    EOT
  }
  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "bucket \"bucket-a\": location is required (set it on the bucket or under defaults)",
      "bucket \"bucket-b\": location is required (set it on the bucket or under defaults)",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "enumerations" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = <<-EOT
      buckets:
        - name: bucket-a
          location: US
          storage_class: COLD
          deletion_policy: KEEP
          public_access_prevention: disabled
          rpo: FAST
    EOT
  }
  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "bucket \"bucket-a\": deletion_policy must be one of DELETE, PREVENT, ABANDON, got \"KEEP\"",
      "bucket \"bucket-a\": public_access_prevention must be one of enforced, inherited, got \"disabled\"",
      "bucket \"bucket-a\": rpo must be one of DEFAULT, ASYNC_TURBO, got \"FAST\"",
      "bucket \"bucket-a\": storage_class must be one of STANDARD, NEARLINE, COLDLINE, ARCHIVE, MULTI_REGIONAL, REGIONAL, got \"COLD\"",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "patterns" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = <<-EOT
      defaults:
        project_id: My_Project
      buckets:
        - name: bucket-a
          location: us central
          kms_key_name: my-key
    EOT
  }
  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "bucket \"bucket-a\": kms_key_name must be a Cloud KMS key name (projects/P/locations/L/keyRings/R/cryptoKeys/K), got \"my-key\"",
      "bucket \"bucket-a\": location must be a location such as US, EU or US-CENTRAL1, got \"us central\"",
      "defaults: project_id must be a valid project ID, got \"My_Project\"",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "booleans" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = <<-EOT
      defaults:
        uniform_bucket_level_access: enabled
      buckets:
        - name: bucket-a
          location: US
          versioning: yes please
          force_destroy: 1
          requester_pays: [true]
    EOT
  }
  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "bucket \"bucket-a\": force_destroy must be true or false, got 1",
      "bucket \"bucket-a\": requester_pays must be true or false, got [true]",
      "bucket \"bucket-a\": versioning must be true or false, got \"yes please\"",
      "defaults: uniform_bucket_level_access must be true or false, got \"enabled\"",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "soft_delete_and_data_locations" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = <<-EOT
      defaults:
        location: US
      buckets:
        - name: too-short
          soft_delete_retention_seconds: 3600
        - name: too-long
          soft_delete_retention_seconds: 7776001
        - name: not-a-number
          soft_delete_retention_seconds: one week
        - name: fraction
          soft_delete_retention_seconds: 604800.5
        - name: empty-locations
          data_locations: []
        - name: string-locations
          data_locations: US-EAST1
    EOT
  }
  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "bucket \"empty-locations\": data_locations must be a non-empty list of region names, got []",
      "bucket \"fraction\": soft_delete_retention_seconds must be 0 (disabled) or a whole number between 604800 (7 days) and 7776000 (90 days), got 604800.5",
      "bucket \"not-a-number\": soft_delete_retention_seconds must be 0 (disabled) or a whole number between 604800 (7 days) and 7776000 (90 days), got \"one week\"",
      "bucket \"string-locations\": data_locations must be a non-empty list of region names, got \"US-EAST1\"",
      "bucket \"too-long\": soft_delete_retention_seconds must be 0 (disabled) or a whole number between 604800 (7 days) and 7776000 (90 days), got 7776001",
      "bucket \"too-short\": soft_delete_retention_seconds must be 0 (disabled) or a whole number between 604800 (7 days) and 7776000 (90 days), got 3600",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "labels" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = <<-EOT
      defaults:
        location: US
      buckets:
        - name: bucket-a
          labels:
            Team: data
            cost_center: CC 1234
            fine: ok
        - name: bucket-b
          labels: [not, a, map]
    EOT
  }
  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "bucket \"bucket-a\": label \"cost_center\" has an invalid value \"CC 1234\" (use lowercase letters, digits, '_' and '-', at most 63 characters)",
      "bucket \"bucket-a\": label key \"Team\" is invalid (use lowercase letters, digits, '_' and '-', start with a letter, at most 63 characters)",
      "bucket \"bucket-b\": labels must be a mapping of key: value pairs, got [\"not\",\"a\",\"map\"]",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "too_many_labels" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = join("\n", concat(
      ["buckets:", "  - name: bucket-a", "    location: US", "    labels:"],
      [for i in range(65) : "      label-${i}: value"],
    ))
  }
  assert {
    condition     = jsonencode(output.errors) == jsonencode(["bucket \"bucket-a\": at most 64 labels are allowed, got 65 (including labels inherited from defaults)"])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "too_many_labels_after_merging_defaults" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    # 40 default labels + 25 bucket labels: each map is fine on its own.
    yaml = join("\n", concat(
      ["defaults:", "  location: US", "  labels:"],
      [for i in range(40) : "    default-${i}: value"],
      ["buckets:", "  - name: bucket-a", "    labels:"],
      [for i in range(25) : "      bucket-${i}: value"],
      ["  - name: bucket-b"],
    ))
  }
  assert {
    condition     = jsonencode(output.errors) == jsonencode(["bucket \"bucket-a\": at most 64 labels are allowed, got 65 (including labels inherited from defaults)"])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "autoclass_values" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = <<-EOT
      defaults:
        location: US
      buckets:
        - name: bucket-a
          autoclass: sometimes
        - name: bucket-b
          autoclass: {enabled: maybe, terminal_storage_class: COLDLINE, extra: 1}
    EOT
  }
  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "bucket \"bucket-a\": autoclass must be true, false or a mapping with enabled and terminal_storage_class, got \"sometimes\"",
      "bucket \"bucket-b\": autoclass.enabled must be true or false, got \"maybe\"",
      "bucket \"bucket-b\": autoclass.terminal_storage_class must be one of NEARLINE, ARCHIVE, got \"COLDLINE\"",
      "bucket \"bucket-b\": unknown attribute(s) in autoclass: extra",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "autoclass_conflicts" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = <<-EOT
      defaults:
        location: US
      buckets:
        - name: bucket-a
          storage_class: NEARLINE
          autoclass: true
        - name: bucket-b
          autoclass: {terminal_storage_class: ARCHIVE}
          lifecycle_rules:
            - action: {type: SetStorageClass, storage_class: COLDLINE}
              condition: {age: 30}
            - action: {type: Delete}
              condition: {age: 365, matches_storage_class: [STANDARD]}
        - name: disabled-is-fine
          storage_class: NEARLINE
          autoclass: {enabled: false}
          lifecycle_rules:
            - action: {type: SetStorageClass, storage_class: COLDLINE}
              condition: {age: 30}
    EOT
  }
  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "bucket \"bucket-a\": storage_class must be STANDARD when autoclass is enabled",
      "bucket \"bucket-b\": autoclass cannot be combined with lifecycle rules that use the SetStorageClass action",
      "bucket \"bucket-b\": autoclass cannot be combined with lifecycle rules that use the matches_storage_class condition",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "retention_policy_values" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = <<-EOT
      defaults:
        location: US
      buckets:
        - name: bucket-a
          retention_policy: 86400
        - name: bucket-b
          retention_policy: {is_locked: true, period: 5}
        - name: bucket-c
          retention_policy: {retention_period: 0, is_locked: no way}
        - name: bucket-d
          retention_policy: {retention_period: 3155760001}
    EOT
  }
  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "bucket \"bucket-a\": retention_policy must be a mapping with retention_period and optional is_locked, got 86400",
      "bucket \"bucket-b\": retention_policy.retention_period is required",
      "bucket \"bucket-b\": unknown attribute(s) in retention_policy: period",
      "bucket \"bucket-c\": retention_policy.is_locked must be true or false, got \"no way\"",
      "bucket \"bucket-c\": retention_policy.retention_period must be a whole number of seconds between 1 and 3155760000, got 0",
      "bucket \"bucket-d\": retention_policy.retention_period must be a whole number of seconds between 1 and 3155760000, got 3155760001",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "logging_and_website_values" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = <<-EOT
      defaults:
        location: US
      buckets:
        - name: bucket-a
          logging: {log_object_prefix: logs/}
        - name: bucket-b
          logging: my-log-bucket
        - name: bucket-c
          website: {index: index.html}
        - name: bucket-d
          website: index.html
        - name: bucket-e
          logging: {log_bucket: logs, log_object_prefix: [a]}
          website: {main_page_suffix: {page: index.html}}
    EOT
  }
  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "bucket \"bucket-a\": logging.log_bucket is required",
      "bucket \"bucket-b\": logging must be a mapping with log_bucket and optional log_object_prefix, got \"my-log-bucket\"",
      "bucket \"bucket-c\": unknown attribute(s) in website: index",
      "bucket \"bucket-d\": website must be a mapping with main_page_suffix and/or not_found_page, got \"index.html\"",
      "bucket \"bucket-e\": logging.log_object_prefix must be a string",
      "bucket \"bucket-e\": website.main_page_suffix must be a string",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "cors_values" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = <<-EOT
      defaults:
        location: US
      buckets:
        - name: bucket-a
          cors: {origin: ["*"]}
        - name: bucket-b
          cors:
            - {}
            - origins: ["*"]
            - origin: "*"
              max_age_seconds: -1
            - method: [GET, [POST]]
    EOT
  }
  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "bucket \"bucket-a\": cors must be a list of CORS rules, got {\"origin\":[\"*\"]}",
      "bucket \"bucket-b\": cors[0]: must be a non-empty mapping with origin, method, response_header and/or max_age_seconds",
      "bucket \"bucket-b\": cors[1]: unknown attribute(s): origins",
      "bucket \"bucket-b\": cors[2]: max_age_seconds must be a non-negative whole number, got -1",
      "bucket \"bucket-b\": cors[2]: origin must be a list of strings, got \"*\"",
      "bucket \"bucket-b\": cors[3]: method must be a list of strings, got [\"GET\",[\"POST\"]]",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "hierarchical_namespace_conflicts" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = <<-EOT
      defaults:
        location: US
      buckets:
        - name: bucket-a
          hierarchical_namespace: true
          uniform_bucket_level_access: false
        - name: bucket-b
          hierarchical_namespace: true
          versioning: true
          retention_policy: {retention_period: 60}
          enable_object_retention: true
          default_event_based_hold: true
        - name: bucket-c
          hierarchical_namespace: false
          versioning: true
    EOT
  }
  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "bucket \"bucket-a\": hierarchical_namespace requires uniform_bucket_level_access: true",
      "bucket \"bucket-b\": hierarchical_namespace cannot be combined with default_event_based_hold",
      "bucket \"bucket-b\": hierarchical_namespace cannot be combined with enable_object_retention",
      "bucket \"bucket-b\": hierarchical_namespace cannot be combined with retention_policy",
      "bucket \"bucket-b\": hierarchical_namespace cannot be combined with versioning",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

# --- Lifecycle rules -------------------------------------------------------------

run "lifecycle_structure" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = <<-EOT
      defaults:
        location: US
      buckets:
        - name: bucket-a
          lifecycle_rules: {action: {type: Delete}}
        - name: bucket-b
          lifecycle_rules:
            - delete-after-30-days
            - condition: {age: 30}
            - action: Delete
              condition: {age: 30}
            - action: {type: Delete, kind: x}
              condition: {age: 30}
              comment: typo
            - action: {type: Delete}
            - action: {type: Delete}
              condition: 30
            - action: {type: Delete}
              condition: {}
            - action: {type: Delete}
              condition: {ages: 30}
    EOT
  }
  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "bucket \"bucket-a\": lifecycle_rules must be a list of rules, got {\"action\":{\"type\":\"Delete\"}}",
      "bucket \"bucket-b\": lifecycle_rules[0]: must be a mapping with action and condition",
      "bucket \"bucket-b\": lifecycle_rules[1]: action is required",
      "bucket \"bucket-b\": lifecycle_rules[2]: action must be a mapping with type and optional storage_class, got \"Delete\"",
      "bucket \"bucket-b\": lifecycle_rules[3]: unknown attribute(s) in action: kind",
      "bucket \"bucket-b\": lifecycle_rules[3]: unknown attribute(s): comment",
      "bucket \"bucket-b\": lifecycle_rules[4]: condition is required",
      "bucket \"bucket-b\": lifecycle_rules[5]: condition must be a mapping of criteria, got 30",
      "bucket \"bucket-b\": lifecycle_rules[6]: condition must set at least one criterion",
      "bucket \"bucket-b\": lifecycle_rules[7]: unknown attribute(s) in condition: ages",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "lifecycle_values" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = <<-EOT
      buckets:
        - name: bucket-a
          location: US
          lifecycle_rules:
            - action: {type: Remove}
              condition: {age: 30}
            - action: {type: SetStorageClass}
              condition: {age: 30}
            - action: {type: SetStorageClass, storage_class: GLACIER}
              condition: {age: 30}
            - action: {type: Delete, storage_class: NEARLINE}
              condition: {age: 30}
            - action: {type: AbortIncompleteMultipartUpload}
              condition: {age: 1, with_state: LIVE}
            - action: {type: Delete}
              condition: {with_state: DELETED}
            - action: {type: Delete}
              condition: {matches_storage_class: [STANDARD, HOT]}
            - action: {type: Delete}
              condition: {age: -1, num_newer_versions: 1.5, size_above_bytes: big}
            - action: {type: Delete}
              condition: {created_before: 01/02/2024, noncurrent_time_before: 2024-01-01T10:00:00Z}
            - action: {type: Delete}
              condition: {matches_prefix: logs/, matches_suffix: [.log, [nested]]}
    EOT
  }
  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "bucket \"bucket-a\": lifecycle_rules[0]: action.type must be one of Delete, SetStorageClass, AbortIncompleteMultipartUpload, got \"Remove\"",
      "bucket \"bucket-a\": lifecycle_rules[1]: action.storage_class must be one of STANDARD, NEARLINE, COLDLINE, ARCHIVE, MULTI_REGIONAL, REGIONAL for SetStorageClass, got null",
      "bucket \"bucket-a\": lifecycle_rules[2]: action.storage_class must be one of STANDARD, NEARLINE, COLDLINE, ARCHIVE, MULTI_REGIONAL, REGIONAL for SetStorageClass, got \"GLACIER\"",
      "bucket \"bucket-a\": lifecycle_rules[3]: action.storage_class is only allowed with the SetStorageClass action",
      "bucket \"bucket-a\": lifecycle_rules[4]: AbortIncompleteMultipartUpload rules only support the age, matches_prefix and matches_suffix conditions",
      "bucket \"bucket-a\": lifecycle_rules[5]: condition.with_state must be one of LIVE, ARCHIVED, ANY, got \"DELETED\"",
      "bucket \"bucket-a\": lifecycle_rules[6]: condition.matches_storage_class must be a non-empty list of STANDARD, NEARLINE, COLDLINE, ARCHIVE, MULTI_REGIONAL, REGIONAL, DURABLE_REDUCED_AVAILABILITY, got [\"STANDARD\",\"HOT\"]",
      "bucket \"bucket-a\": lifecycle_rules[7]: condition.age must be a non-negative whole number, got -1",
      "bucket \"bucket-a\": lifecycle_rules[7]: condition.num_newer_versions must be a non-negative whole number, got 1.5",
      "bucket \"bucket-a\": lifecycle_rules[7]: condition.size_above_bytes must be a non-negative whole number, got \"big\"",
      "bucket \"bucket-a\": lifecycle_rules[8]: condition.created_before must be a date in YYYY-MM-DD format, got \"01/02/2024\"",
      "bucket \"bucket-a\": lifecycle_rules[8]: condition.noncurrent_time_before must be a date in YYYY-MM-DD format, got \"2024-01-01T10:00:00Z\"",
      "bucket \"bucket-a\": lifecycle_rules[9]: condition.matches_prefix must be a list of strings, got \"logs/\"",
      "bucket \"bucket-a\": lifecycle_rules[9]: condition.matches_suffix must be a list of strings, got [\".log\",[\"nested\"]]",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "too_many_lifecycle_rules" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = join("\n", concat(
      ["buckets:", "  - name: bucket-a", "    location: US", "    lifecycle_rules:"],
      [for i in range(101) : "      - {action: {type: Delete}, condition: {age: ${i + 1}}}"],
    ))
  }
  assert {
    condition     = jsonencode(output.errors) == jsonencode(["bucket \"bucket-a\": at most 100 lifecycle_rules are allowed, got 101"])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "defaults_are_validated_once" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    # An invalid value under defaults is reported once, not once per bucket.
    yaml = <<-EOT
      defaults:
        location: US
        storage_class: SUPERCOLD
        lifecycle_rules:
          - action: {type: Delete}
            condition: {age: -5}
      buckets:
        - name: bucket-a
        - name: bucket-b
    EOT
  }
  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "defaults: lifecycle_rules[0]: condition.age must be a non-negative whole number, got -5",
      "defaults: storage_class must be one of STANDARD, NEARLINE, COLDLINE, ARCHIVE, MULTI_REGIONAL, REGIONAL, got \"SUPERCOLD\"",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

# --- IAM ---------------------------------------------------------------------------

run "iam_structure" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = <<-EOT
      defaults:
        location: US
      buckets:
        - name: bucket-a
          iam: {role: roles/storage.objectViewer}
        - name: bucket-b
          iam:
            - roles/storage.objectViewer
            - members: [user:a@example.com]
            - role: storage.objectViewer
              members: [user:a@example.com]
            - role: roles/storage.objectAdmin
            - role: roles/storage.objectCreator
              member: [user:a@example.com]
            - role: roles/storage.legacyBucketReader
              members: user:a@example.com
              mode: exclusive
    EOT
  }
  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "bucket \"bucket-a\": iam must be a list of role bindings, got {\"role\":\"roles/storage.objectViewer\"}",
      "bucket \"bucket-b\": iam[0]: must be a mapping with role and principals",
      "bucket \"bucket-b\": iam[1]: role is required",
      "bucket \"bucket-b\": iam[2] (storage.objectViewer): role must look like roles/NAME, projects/PROJECT/roles/NAME or organizations/ORG/roles/NAME, got \"storage.objectViewer\"",
      "bucket \"bucket-b\": iam[3] (roles/storage.objectAdmin): at least one principal is required (members, users, groups, service_accounts or domains)",
      "bucket \"bucket-b\": iam[4] (roles/storage.objectCreator): at least one principal is required (members, users, groups, service_accounts or domains)",
      "bucket \"bucket-b\": iam[4] (roles/storage.objectCreator): unknown attribute(s): member",
      "bucket \"bucket-b\": iam[5] (roles/storage.legacyBucketReader): at least one principal is required (members, users, groups, service_accounts or domains)",
      "bucket \"bucket-b\": iam[5] (roles/storage.legacyBucketReader): members must be a list, got \"user:a@example.com\"",
      "bucket \"bucket-b\": iam[5] (roles/storage.legacyBucketReader): mode must be one of authoritative, additive, got \"exclusive\"",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "iam_invalid_principals" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = <<-EOT
      defaults:
        location: US
      buckets:
        - name: bucket-a
          iam:
            - role: roles/storage.objectViewer
              members:
                - alice@example.com
                - User:bob@example.com
                - serviceaccount:sa@p.iam.gserviceaccount.com
                - domain:not_a_domain
                - allusers
                - user:missing-at.example.com
                - deleted:user:old@example.com?uid=123
                - principal:/missing-slash
            - role: roles/storage.objectAdmin
              users: [user:carol@example.com, dave at example.com]
              groups: [team@example.com]
              service_accounts: [etl]
              domains: [example.com, exa mple.com, "*.example.com"]
    EOT
  }
  assert {
    condition     = length(output.errors) == 13
    error_message = "Expected 13 errors, got ${length(output.errors)}: ${jsonencode(output.errors)}"
  }
  assert {
    # One message checked in full; the others by prefix below.
    condition     = contains(output.errors, "bucket \"bucket-a\": iam[0] (roles/storage.objectViewer): invalid member \"alice@example.com\" (expected user:EMAIL, group:EMAIL, serviceAccount:EMAIL, domain:DOMAIN, allUsers, allAuthenticatedUsers, projectOwner:PROJECT_ID, projectEditor:PROJECT_ID, projectViewer:PROJECT_ID, principal://... or principalSet://...)")
    error_message = "Got: ${jsonencode(output.errors)}"
  }
  assert {
    condition = alltrue([
      for member in ["User:bob@example.com", "serviceaccount:sa@p.iam.gserviceaccount.com", "domain:not_a_domain", "allusers", "user:missing-at.example.com", "deleted:user:old@example.com?uid=123", "principal:/missing-slash"] :
      anytrue([for e in output.errors : startswith(e, "bucket \"bucket-a\": iam[0] (roles/storage.objectViewer): invalid member ${jsonencode(member)} (expected ")])
    ])
    error_message = "Every malformed member should be reported: ${jsonencode(output.errors)}"
  }
  assert {
    condition = alltrue([for expected in [
      "bucket \"bucket-a\": iam[1] (roles/storage.objectAdmin): invalid email \"user:carol@example.com\" in users (use a bare address such as name@example.com; the user: prefix is added automatically)",
      "bucket \"bucket-a\": iam[1] (roles/storage.objectAdmin): invalid email \"dave at example.com\" in users (use a bare address such as name@example.com; the user: prefix is added automatically)",
      "bucket \"bucket-a\": iam[1] (roles/storage.objectAdmin): invalid email \"etl\" in service_accounts (use a bare address such as name@example.com; the serviceAccount: prefix is added automatically)",
      "bucket \"bucket-a\": iam[1] (roles/storage.objectAdmin): invalid domain \"exa mple.com\" in domains (expected a domain such as example.com)",
      "bucket \"bucket-a\": iam[1] (roles/storage.objectAdmin): invalid domain \"*.example.com\" in domains (expected a domain such as example.com)",
    ] : contains(output.errors, expected)])
    error_message = "Shorthand entries should be validated: ${jsonencode(output.errors)}"
  }
}

run "iam_conditions" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = <<-EOT
      defaults:
        location: US
      buckets:
        - name: bucket-a
          iam:
            - role: roles/storage.objectViewer
              members: [user:a@example.com]
              condition: request.time < timestamp("2027-01-01T00:00:00Z")
            - role: roles/storage.objectAdmin
              members: [user:a@example.com]
              condition: {expression: "true", note: x}
            - role: roles/storage.objectCreator
              members: [user:a@example.com]
              condition: {title: t, description: [a]}
        - name: bucket-b
          uniform_bucket_level_access: false
          iam:
            - role: roles/storage.objectViewer
              members: [user:a@example.com]
              condition: {title: t, expression: "true"}
    EOT
  }
  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "bucket \"bucket-a\": iam[0] (roles/storage.objectViewer): condition must be a mapping with title, expression and optional description",
      "bucket \"bucket-a\": iam[1] (roles/storage.objectAdmin): condition.title is required",
      "bucket \"bucket-a\": iam[1] (roles/storage.objectAdmin): unknown attribute(s) in condition: note",
      "bucket \"bucket-a\": iam[2] (roles/storage.objectCreator): condition.description must be a string",
      "bucket \"bucket-a\": iam[2] (roles/storage.objectCreator): condition.expression is required",
      "bucket \"bucket-b\": iam[0] (roles/storage.objectViewer): IAM conditions require uniform_bucket_level_access: true",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "public_principals_need_public_access" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = <<-EOT
      defaults:
        location: US
      buckets:
        - name: default-enforced
          iam:
            - role: roles/storage.objectViewer
              members: [allUsers]
        - name: explicitly-enforced
          public_access_prevention: enforced
          iam:
            - role: roles/storage.objectViewer
              members: [allAuthenticatedUsers]
        - name: inherited
          public_access_prevention: inherited
          iam:
            - role: roles/storage.objectViewer
              members: [allUsers, allAuthenticatedUsers]
        - name: left-to-gcp
          public_access_prevention: ~
          iam:
            - role: roles/storage.objectViewer
              members: [allUsers]
    EOT
  }
  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "bucket \"default-enforced\": iam[0] (roles/storage.objectViewer): allUsers and allAuthenticatedUsers cannot be granted while public_access_prevention is enforced; set public_access_prevention: inherited on this bucket",
      "bucket \"explicitly-enforced\": iam[0] (roles/storage.objectViewer): allUsers and allAuthenticatedUsers cannot be granted while public_access_prevention is enforced; set public_access_prevention: inherited on this bucket",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

run "iam_duplicates" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = <<-EOT
      defaults:
        location: US
      buckets:
        - name: bucket-a
          iam:
            - role: roles/storage.objectViewer
              members: [user:a@example.com]
            - role: roles/storage.objectAdmin
              members: [user:b@example.com]
            # Mixing modes for the same role would make the two resources
            # fight over the same binding.
            - role: roles/storage.objectViewer
              mode: additive
              members: [user:c@example.com]
        - name: bucket-b
          iam:
            - role: roles/storage.objectViewer
              members: [user:a@example.com]
              condition: {title: temp, expression: "true"}
            - role: roles/storage.objectViewer
              members: [user:b@example.com]
              condition: {title: temp, expression: "false"}
            - role: roles/storage.objectViewer
              members: [user:c@example.com]
              condition: {title: other, expression: "true"}
            - role: roles/storage.objectViewer
              members: [user:d@example.com]
    EOT
  }
  assert {
    condition = jsonencode(output.errors) == jsonencode([
      "bucket \"bucket-a\": role roles/storage.objectViewer is bound in more than one iam entry (iam[0], iam[2]); merge them, or give each condition a distinct title",
      "bucket \"bucket-b\": role roles/storage.objectViewer with condition \"temp\" is bound in more than one iam entry (iam[0], iam[1]); merge them, or give each condition a distinct title",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
}

# --- Reporting ---------------------------------------------------------------------

run "errors_are_aggregated_and_sorted" {
  command = plan
  module {
    source = "./modules/config"
  }
  variables {
    yaml = <<-EOT
      extra: 1
      defaults:
        colour: blue
      buckets:
        - name: zeta
          location: US
          versioning: maybe
        - name: alpha
    EOT
  }
  assert {
    # Document-level errors first, then everything else sorted by bucket.
    condition = jsonencode(output.errors) == jsonencode([
      "unknown top-level key(s): extra (allowed: buckets, defaults and x-* extension keys)",
      "bucket \"alpha\": location is required (set it on the bucket or under defaults)",
      "bucket \"zeta\": versioning must be true or false, got \"maybe\"",
      "defaults: unknown attribute(s): colour",
    ])
    error_message = "Got: ${jsonencode(output.errors)}"
  }
  assert {
    condition     = length(output.buckets) == 0 && length(output.iam_bindings) == 0 && length(output.iam_members) == 0
    error_message = "Valid buckets must not be produced while any error exists."
  }
}
