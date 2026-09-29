# Unit tests for modules/config: defaults, precedence and normalisation of
# valid documents. Each run plans the configuration module on its own (it has
# no providers), so outputs are fully known and can be compared exactly.

run "builtin_defaults" {
  command = plan

  module {
    source = "./modules/config"
  }

  variables {
    yaml = <<-EOT
      buckets:
        - name: minimal
          location: us
    EOT
  }

  assert {
    condition     = length(output.errors) == 0
    error_message = "Unexpected errors: ${jsonencode(output.errors)}"
  }

  assert {
    condition = jsonencode(output.buckets) == jsonencode({
      minimal = {
        autoclass                     = null
        cors                          = []
        data_locations                = null
        default_event_based_hold      = null
        deletion_policy               = null
        enable_object_retention       = null
        force_destroy                 = false
        hierarchical_namespace        = null
        kms_key_name                  = null
        labels                        = {}
        lifecycle_rules               = []
        location                      = "US"
        logging                       = null
        name                          = "minimal"
        project_id                    = null
        public_access_prevention      = "enforced"
        requester_pays                = null
        retention_policy              = null
        rpo                           = null
        soft_delete_retention_seconds = null
        storage_class                 = "STANDARD"
        uniform_bucket_level_access   = true
        versioning                    = false
        website                       = null
      }
    })
    error_message = "Unexpected normalised bucket: ${jsonencode(output.buckets)}"
  }

  assert {
    condition     = length(output.iam_bindings) == 0 && length(output.iam_members) == 0
    error_message = "No IAM was declared."
  }
}

run "defaults_and_overrides" {
  command = plan

  module {
    source = "./modules/config"
  }

  variables {
    yaml = <<-EOT
      defaults:
        location: EU
        storage_class: NEARLINE
        versioning: true
        kms_key_name: projects/p/locations/eu/keyRings/r/cryptoKeys/k
        lifecycle_rules:
          - action: {type: Delete}
            condition: {age: 365}
      buckets:
        - name: inherits
        - name: overrides
          location: US-EAST1
          storage_class: STANDARD
          versioning: false
          lifecycle_rules: []
        - name: unsets
          # A key set to null wins over defaults: the attribute is left to
          # the provider/GCP default.
          kms_key_name: ~
          public_access_prevention: ~
          lifecycle_rules: ~
    EOT
  }

  assert {
    condition     = length(output.errors) == 0
    error_message = "Unexpected errors: ${jsonencode(output.errors)}"
  }

  assert {
    condition     = output.buckets["inherits"].location == "EU" && output.buckets["inherits"].storage_class == "NEARLINE" && output.buckets["inherits"].versioning == true
    error_message = "Defaults should apply: ${jsonencode(output.buckets["inherits"])}"
  }

  assert {
    condition     = output.buckets["inherits"].kms_key_name == "projects/p/locations/eu/keyRings/r/cryptoKeys/k" && length(output.buckets["inherits"].lifecycle_rules) == 1
    error_message = "Default KMS key and lifecycle rules should apply."
  }

  assert {
    condition     = output.buckets["overrides"].location == "US-EAST1" && output.buckets["overrides"].storage_class == "STANDARD" && output.buckets["overrides"].versioning == false && length(output.buckets["overrides"].lifecycle_rules) == 0
    error_message = "Bucket values should override defaults: ${jsonencode(output.buckets["overrides"])}"
  }

  assert {
    condition     = output.buckets["unsets"].kms_key_name == null && output.buckets["unsets"].public_access_prevention == null && length(output.buckets["unsets"].lifecycle_rules) == 0
    error_message = "Explicit nulls should unset defaults: ${jsonencode(output.buckets["unsets"])}"
  }

  assert {
    condition     = output.buckets["unsets"].storage_class == "NEARLINE" && output.buckets["unsets"].uniform_bucket_level_access == true
    error_message = "Keys that are not set on the bucket should still be inherited."
  }
}

run "labels_merge" {
  command = plan

  module {
    source = "./modules/config"
  }

  variables {
    labels = {
      owner = "platform"
      env   = "from-variable"
    }
    yaml = <<-EOT
      defaults:
        location: US
        labels:
          env: prod
          team: data
      buckets:
        - name: merged
          labels:
            team: ml
            cost: 1234
            critical: true
        - name: defaults-only
        - name: null-labels
          labels: ~
        # Only numbers and booleans: there is no common type to convert the
        # map to, so each value must be converted on its own.
        - name: numbers-and-bools
          labels: {count: 5, flag: true}
    EOT
  }

  assert {
    condition     = jsonencode(output.buckets["numbers-and-bools"].labels) == jsonencode({ owner = "platform", env = "prod", team = "data", count = "5", flag = "true" })
    error_message = "Number and boolean label values must be kept: ${jsonencode(output.buckets["numbers-and-bools"].labels)}"
  }

  assert {
    condition = jsonencode(output.buckets["merged"].labels) == jsonencode({
      owner    = "platform"
      env      = "prod"
      team     = "ml"
      cost     = "1234"
      critical = "true"
    })
    error_message = "Labels should merge variable < defaults < bucket and be strings: ${jsonencode(output.buckets["merged"].labels)}"
  }

  assert {
    condition     = jsonencode(output.buckets["defaults-only"].labels) == jsonencode({ owner = "platform", env = "prod", team = "data" })
    error_message = "Bucket without labels should get variable and default labels."
  }

  assert {
    condition     = jsonencode(output.buckets["null-labels"].labels) == jsonencode({ owner = "platform", env = "prod", team = "data" })
    error_message = "labels: ~ should not drop inherited labels."
  }
}

run "project_precedence" {
  command = plan

  module {
    source = "./modules/config"
  }

  variables {
    project_id = "variable-project"
    yaml       = <<-EOT
      defaults:
        location: US
        project_id: defaults-project
      buckets:
        - name: from-defaults
        - name: from-bucket
          project_id: bucket-project
        - name: from-variable
          project_id: ~
    EOT
  }

  assert {
    condition     = output.buckets["from-defaults"].project_id == "defaults-project"
    error_message = "defaults.project_id should apply."
  }

  assert {
    condition     = output.buckets["from-bucket"].project_id == "bucket-project"
    error_message = "The bucket's project_id should win."
  }

  assert {
    condition     = output.buckets["from-variable"].project_id == "variable-project"
    error_message = "A null project_id should fall back to var.project_id."
  }
}

run "project_falls_back_to_provider" {
  command = plan

  module {
    source = "./modules/config"
  }

  variables {
    yaml = <<-EOT
      buckets:
        - name: no-project
          location: US
    EOT
  }

  assert {
    condition     = output.buckets["no-project"].project_id == null
    error_message = "Without any project_id the provider project should be used (null)."
  }
}

run "name_prefix" {
  command = plan

  module {
    source = "./modules/config"
  }

  variables {
    name_prefix = "acme-prod-"
    yaml        = <<-EOT
      buckets:
        - name: data
          location: US
          iam:
            - role: roles/storage.objectViewer
              members: [group:readers@example.com]
    EOT
  }

  assert {
    condition     = jsonencode(keys(output.buckets)) == jsonencode(["data"]) && output.buckets["data"].name == "acme-prod-data"
    error_message = "The prefix should apply to the bucket name but not to the key."
  }

  assert {
    condition     = jsonencode(keys(output.iam_bindings)) == jsonencode(["data|roles/storage.objectViewer"]) && output.iam_bindings["data|roles/storage.objectViewer"].bucket == "data"
    error_message = "IAM entries should reference the bucket by its key."
  }
}

run "case_normalisation" {
  command = plan

  module {
    source = "./modules/config"
  }

  variables {
    yaml = <<-EOT
      buckets:
        - name: mixed-case
          location: europe-west1
          storage_class: nearline
          public_access_prevention: Enforced
          rpo: default
          deletion_policy: prevent
          lifecycle_rules:
            - action: {type: setstorageclass, storage_class: coldline}
              condition: {age: 30, with_state: live, matches_storage_class: [nearline]}
            - action: {type: DELETE}
              condition: {age: 400}
            - action: {type: abortincompletemultipartupload}
              condition: {age: 1}
        - name: dual-region
          location: us
          data_locations: [us-east1, us-west1]
          autoclass: {terminal_storage_class: archive}
    EOT
  }

  assert {
    condition     = length(output.errors) == 0
    error_message = "Unexpected errors: ${jsonencode(output.errors)}"
  }

  assert {
    condition = (
      output.buckets["mixed-case"].location == "EUROPE-WEST1" &&
      output.buckets["mixed-case"].storage_class == "NEARLINE" &&
      output.buckets["mixed-case"].public_access_prevention == "enforced" &&
      output.buckets["mixed-case"].rpo == "DEFAULT" &&
      output.buckets["mixed-case"].deletion_policy == "PREVENT"
    )
    error_message = "Enumerations should be normalised: ${jsonencode(output.buckets["mixed-case"])}"
  }

  assert {
    condition = (
      jsonencode([for r in output.buckets["mixed-case"].lifecycle_rules : r.action_type]) == jsonencode(["SetStorageClass", "Delete", "AbortIncompleteMultipartUpload"]) &&
      output.buckets["mixed-case"].lifecycle_rules[0].action_storage_class == "COLDLINE" &&
      output.buckets["mixed-case"].lifecycle_rules[0].with_state == "LIVE" &&
      jsonencode(output.buckets["mixed-case"].lifecycle_rules[0].matches_storage_class) == jsonencode(["NEARLINE"])
    )
    error_message = "Lifecycle values should be normalised: ${jsonencode(output.buckets["mixed-case"].lifecycle_rules)}"
  }

  assert {
    condition     = jsonencode(output.buckets["dual-region"].data_locations) == jsonencode(["US-EAST1", "US-WEST1"]) && jsonencode(output.buckets["dual-region"].autoclass) == jsonencode({ enabled = true, terminal_storage_class = "ARCHIVE" })
    error_message = "data_locations and autoclass should be normalised: ${jsonencode(output.buckets["dual-region"])}"
  }
}

run "lifecycle_dates_and_zero_values" {
  command = plan

  module {
    source = "./modules/config"
  }

  variables {
    yaml = <<-EOT
      buckets:
        - name: dates
          location: US
          lifecycle_rules:
            # Unquoted YAML dates decode as timestamps; they must still reach
            # the API as YYYY-MM-DD.
            - action: {type: Delete}
              condition:
                created_before: 2024-01-01
                custom_time_before: "2024-02-03"
                noncurrent_time_before: 2024-03-04
            # Zero values are dropped by the provider unless flagged.
            - action: {type: Delete}
              condition:
                age: 0
                num_newer_versions: 0
                days_since_custom_time: 0
                days_since_noncurrent_time: 0
            - action: {type: Delete}
              condition:
                age: 5
                num_newer_versions: 2
                size_above_bytes: 1048576
                size_below_bytes: 1073741824
                matches_prefix: [logs/, 2024]
                matches_suffix: [.log]
    EOT
  }

  assert {
    condition     = length(output.errors) == 0
    error_message = "Unexpected errors: ${jsonencode(output.errors)}"
  }

  assert {
    condition = (
      output.buckets["dates"].lifecycle_rules[0].created_before == "2024-01-01" &&
      output.buckets["dates"].lifecycle_rules[0].custom_time_before == "2024-02-03" &&
      output.buckets["dates"].lifecycle_rules[0].noncurrent_time_before == "2024-03-04"
    )
    error_message = "Dates should be YYYY-MM-DD: ${jsonencode(output.buckets["dates"].lifecycle_rules[0])}"
  }

  assert {
    condition = (
      output.buckets["dates"].lifecycle_rules[1].send_age_if_zero &&
      output.buckets["dates"].lifecycle_rules[1].send_num_newer_versions_if_zero &&
      output.buckets["dates"].lifecycle_rules[1].send_days_since_custom_time_if_zero &&
      output.buckets["dates"].lifecycle_rules[1].send_days_since_noncurrent_time_if_zero
    )
    error_message = "Zero values should be flagged for sending: ${jsonencode(output.buckets["dates"].lifecycle_rules[1])}"
  }

  assert {
    condition = (
      !output.buckets["dates"].lifecycle_rules[2].send_age_if_zero &&
      !output.buckets["dates"].lifecycle_rules[2].send_num_newer_versions_if_zero &&
      !output.buckets["dates"].lifecycle_rules[0].send_age_if_zero
    )
    error_message = "Only zero values should be flagged."
  }

  assert {
    condition = (
      output.buckets["dates"].lifecycle_rules[2].size_above_bytes == 1048576 &&
      output.buckets["dates"].lifecycle_rules[2].size_below_bytes == 1073741824 &&
      jsonencode(output.buckets["dates"].lifecycle_rules[2].matches_prefix) == jsonencode(["logs/", "2024"]) &&
      jsonencode(output.buckets["dates"].lifecycle_rules[2].matches_suffix) == jsonencode([".log"])
    )
    error_message = "Rule criteria should be passed through: ${jsonencode(output.buckets["dates"].lifecycle_rules[2])}"
  }
}

run "strings_are_converted" {
  command = plan

  module {
    source = "./modules/config"
  }

  variables {
    yaml = <<-EOT
      buckets:
        - name: strings
          location: US
          versioning: "true"
          force_destroy: "false"
          soft_delete_retention_seconds: "604800"
          retention_policy:
            retention_period: "3155760000"
            is_locked: "false"
    EOT
  }

  assert {
    condition     = length(output.errors) == 0
    error_message = "Unexpected errors: ${jsonencode(output.errors)}"
  }

  assert {
    condition = (
      output.buckets["strings"].versioning == true &&
      output.buckets["strings"].force_destroy == false &&
      output.buckets["strings"].soft_delete_retention_seconds == 604800 &&
      jsonencode(output.buckets["strings"].retention_policy) == jsonencode({ retention_period = "3155760000", is_locked = false })
    )
    error_message = "Quoted booleans and numbers should be converted: ${jsonencode(output.buckets["strings"])}"
  }
}

run "autoclass_forms" {
  command = plan

  module {
    source = "./modules/config"
  }

  variables {
    yaml = <<-EOT
      defaults:
        location: US
      buckets:
        - name: shorthand-on
          autoclass: true
        - name: shorthand-off
          autoclass: false
        - name: explicit-off
          autoclass: {enabled: false}
        - name: not-set
    EOT
  }

  assert {
    condition = (
      jsonencode(output.buckets["shorthand-on"].autoclass) == jsonencode({ enabled = true, terminal_storage_class = null }) &&
      jsonencode(output.buckets["shorthand-off"].autoclass) == jsonencode({ enabled = false, terminal_storage_class = null }) &&
      jsonencode(output.buckets["explicit-off"].autoclass) == jsonencode({ enabled = false, terminal_storage_class = null }) &&
      output.buckets["not-set"].autoclass == null
    )
    error_message = "Autoclass forms are wrong: ${jsonencode({ for k, b in output.buckets : k => b.autoclass })}"
  }
}

run "optional_blocks" {
  command = plan

  module {
    source = "./modules/config"
  }

  variables {
    yaml = <<-EOT
      buckets:
        - name: blocks
          location: US
          logging: {log_bucket: my-logs}
          website: {main_page_suffix: index.html}
          retention_policy: {retention_period: 60}
          cors:
            - origin: ["*"]
              method: [GET]
            - response_header: [Content-Type]
              max_age_seconds: 0
    EOT
  }

  assert {
    condition     = length(output.errors) == 0
    error_message = "Unexpected errors: ${jsonencode(output.errors)}"
  }

  assert {
    condition = (
      jsonencode(output.buckets["blocks"].logging) == jsonencode({ log_bucket = "my-logs", log_object_prefix = null }) &&
      jsonencode(output.buckets["blocks"].website) == jsonencode({ main_page_suffix = "index.html", not_found_page = null }) &&
      jsonencode(output.buckets["blocks"].retention_policy) == jsonencode({ retention_period = "60", is_locked = null })
    )
    error_message = "Optional blocks are wrong: ${jsonencode(output.buckets["blocks"])}"
  }

  assert {
    condition = jsonencode(output.buckets["blocks"].cors) == jsonencode([
      { max_age_seconds = null, method = ["GET"], origin = ["*"], response_header = null },
      { max_age_seconds = 0, method = null, origin = null, response_header = ["Content-Type"] },
    ])
    error_message = "CORS rules are wrong: ${jsonencode(output.buckets["blocks"].cors)}"
  }
}

run "iam_principals" {
  command = plan

  module {
    source = "./modules/config"
  }

  variables {
    yaml = <<-EOT
      buckets:
        - name: iam
          location: US
          public_access_prevention: inherited
          iam:
            - role: roles/storage.objectViewer
              members:
                - user:Alice@Example.com
                - group:Readers@example.com
                - serviceAccount:Reporting@my-project.iam.gserviceaccount.com
                - domain:Example.com
                - allUsers
                - allAuthenticatedUsers
                - projectViewer:my-project
                - principal://iam.googleapis.com/projects/1/locations/global/workloadIdentityPools/p.svc.id.goog/subject/ns/NS/sa/Reader
                - principalSet://iam.googleapis.com/projects/1/locations/global/workloadIdentityPools/github/attribute.repository/Org/Repo
              # Shorthand lists; duplicates of the members above collapse,
              # whatever their case.
              users: [ALICE@example.com, Bob@Example.com]
              groups: [readers@EXAMPLE.com]
              service_accounts: [ETL@my-project.iam.gserviceaccount.com]
              domains: [Partner.Example.org]
            - role: organizations/123456789/roles/customReader
              members: [projectOwner:my-project, projectEditor:my-project]
            - role: projects/my-project/roles/custom.writer
              members: [group:writers@example.com]
    EOT
  }

  assert {
    condition     = length(output.errors) == 0
    error_message = "Unexpected errors: ${jsonencode(output.errors)}"
  }

  assert {
    condition = jsonencode(output.iam_bindings["iam|roles/storage.objectViewer"].members) == jsonencode([
      "allAuthenticatedUsers",
      "allUsers",
      "domain:example.com",
      "domain:partner.example.org",
      "group:readers@example.com",
      "principal://iam.googleapis.com/projects/1/locations/global/workloadIdentityPools/p.svc.id.goog/subject/ns/NS/sa/Reader",
      "principalSet://iam.googleapis.com/projects/1/locations/global/workloadIdentityPools/github/attribute.repository/Org/Repo",
      "projectViewer:my-project",
      "serviceAccount:etl@my-project.iam.gserviceaccount.com",
      "serviceAccount:reporting@my-project.iam.gserviceaccount.com",
      "user:alice@example.com",
      "user:bob@example.com",
    ])
    error_message = "Members should be merged, lower-cased (emails/domains only), deduplicated and sorted: ${jsonencode(output.iam_bindings["iam|roles/storage.objectViewer"].members)}"
  }

  assert {
    condition     = jsonencode(output.iam_bindings["iam|organizations/123456789/roles/customReader"].members) == jsonencode(["projectEditor:my-project", "projectOwner:my-project"])
    error_message = "Organization custom roles and convenience values should be accepted."
  }

  assert {
    condition     = output.iam_bindings["iam|projects/my-project/roles/custom.writer"].role == "projects/my-project/roles/custom.writer"
    error_message = "Project custom roles should be accepted."
  }
}

run "iam_modes_and_conditions" {
  command = plan

  module {
    source = "./modules/config"
  }

  variables {
    yaml = <<-EOT
      buckets:
        - name: modes
          location: US
          iam:
            # Same role three times: unconditional, and two distinct
            # conditions. Mixing modes is fine across different conditions.
            - role: roles/storage.objectViewer
              members: [group:readers@example.com]
            - role: roles/storage.objectViewer
              members: [group:contractors@example.com]
              condition:
                title: expires-2027
                description: Temporary access
                expression: request.time < timestamp("2027-01-01T00:00:00Z")
            - role: roles/storage.objectViewer
              mode: additive
              members: [user:auditor@example.com, user:backup@example.com]
              condition:
                title: audit-prefix
                expression: resource.name.startsWith("projects/_/buckets/modes/objects/audit/")
            - role: roles/storage.objectAdmin
              mode: ADDITIVE
              service_accounts: [etl@my-project.iam.gserviceaccount.com]
            - role: roles/storage.objectCreator
              mode: authoritative
              members: [user:uploader@example.com]
    EOT
  }

  assert {
    condition     = length(output.errors) == 0
    error_message = "Unexpected errors: ${jsonencode(output.errors)}"
  }

  assert {
    condition = jsonencode(sort(keys(output.iam_bindings))) == jsonencode([
      "modes|roles/storage.objectCreator",
      "modes|roles/storage.objectViewer",
      "modes|roles/storage.objectViewer|expires-2027",
    ])
    error_message = "Unexpected authoritative bindings: ${jsonencode(keys(output.iam_bindings))}"
  }

  assert {
    condition = jsonencode(sort(keys(output.iam_members))) == jsonencode([
      "modes|roles/storage.objectAdmin|serviceAccount:etl@my-project.iam.gserviceaccount.com",
      "modes|roles/storage.objectViewer|audit-prefix|user:auditor@example.com",
      "modes|roles/storage.objectViewer|audit-prefix|user:backup@example.com",
    ])
    error_message = "Unexpected additive grants: ${jsonencode(keys(output.iam_members))}"
  }

  assert {
    condition = jsonencode(output.iam_bindings["modes|roles/storage.objectViewer|expires-2027"].condition) == jsonencode({
      title       = "expires-2027"
      description = "Temporary access"
      expression  = "request.time < timestamp(\"2027-01-01T00:00:00Z\")"
    })
    error_message = "The condition should be passed through."
  }

  assert {
    condition     = output.iam_bindings["modes|roles/storage.objectViewer"].condition == null && output.iam_members["modes|roles/storage.objectAdmin|serviceAccount:etl@my-project.iam.gserviceaccount.com"].condition == null
    error_message = "Unconditional entries should have a null condition."
  }

  assert {
    condition = jsonencode(output.iam_members["modes|roles/storage.objectViewer|audit-prefix|user:auditor@example.com"]) == jsonencode({
      bucket = "modes"
      role   = "roles/storage.objectViewer"
      member = "user:auditor@example.com"
      condition = {
        title       = "audit-prefix"
        description = null
        expression  = "resource.name.startsWith(\"projects/_/buckets/modes/objects/audit/\")"
      }
    })
    error_message = "Unexpected additive grant: ${jsonencode(output.iam_members["modes|roles/storage.objectViewer|audit-prefix|user:auditor@example.com"])}"
  }
}

run "empty_bucket_lists" {
  command = plan

  module {
    source = "./modules/config"
  }

  variables {
    yaml = <<-EOT
      defaults:
        location: US
      buckets: []
    EOT
  }

  assert {
    condition     = length(output.errors) == 0 && length(output.buckets) == 0
    error_message = "An empty bucket list is valid."
  }
}

run "null_bucket_list" {
  command = plan

  module {
    source = "./modules/config"
  }

  variables {
    # Every bucket commented out: `buckets:` decodes to null.
    yaml = <<-EOT
      buckets:
      #  - name: retired
      #    location: US
    EOT
  }

  assert {
    condition     = length(output.errors) == 0 && length(output.buckets) == 0
    error_message = "A null bucket list is valid: ${jsonencode(output.errors)}"
  }
}

run "extension_keys_and_anchors" {
  command = plan

  module {
    source = "./modules/config"
  }

  variables {
    yaml = <<-EOT
      x-base: &base
        location: EU
        versioning: true
      x-readers: &readers
        role: roles/storage.objectViewer
        groups: [readers@example.com]
      buckets:
        - <<: *base
          name: merged-from-anchor
          iam: [*readers]
        - <<: *base
          name: override-after-merge
          versioning: false
          iam:
            - *readers
            - role: roles/storage.objectAdmin
              users: [admin@example.com]
    EOT
  }

  assert {
    condition     = length(output.errors) == 0
    error_message = "x-* keys should be ignored and anchors should expand: ${jsonencode(output.errors)}"
  }

  assert {
    condition     = output.buckets["merged-from-anchor"].location == "EU" && output.buckets["merged-from-anchor"].versioning == true && output.buckets["override-after-merge"].versioning == false
    error_message = "YAML merge keys should work."
  }

  assert {
    condition     = length(output.iam_bindings) == 3 && jsonencode(output.iam_bindings["override-after-merge|roles/storage.objectViewer"].members) == jsonencode(["group:readers@example.com"])
    error_message = "Aliased IAM entries should expand: ${jsonencode(keys(output.iam_bindings))}"
  }
}

run "valid_bucket_names" {
  command = plan

  module {
    source = "./modules/config"
  }

  variables {
    yaml = <<-EOT
      defaults:
        location: US
      buckets:
        - name: abc
        - name: a_b-c.d
        - name: "123"
        - name: 456
        - name: a-name-that-is-exactly-sixty-three-characters-long-abcdefghijkl
        - name: www.example.com
    EOT
  }

  assert {
    condition     = length(output.errors) == 0
    error_message = "Unexpected errors: ${jsonencode(output.errors)}"
  }

  assert {
    condition     = contains(keys(output.buckets), "456") && output.buckets["456"].name == "456"
    error_message = "Numeric names should be accepted as strings."
  }
}
