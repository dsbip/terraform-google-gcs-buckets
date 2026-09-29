# Configuration layer of the GCS bucket module.
#
# Decodes the YAML document, validates it against the schema documented in
# CLAUDE.md, applies defaults and normalises everything into consistently typed
# maps that the root module turns into resources. It has no providers and no
# resources, so `terraform test` can plan it directly and assert on the exact
# error messages.
#
# YAML is untyped: every access to user data goes through try()/can() so that
# bad input becomes an entry in local.errors instead of an evaluation error.
# The normalised maps at the end of this file are only built when the whole
# document is valid (the `if local.valid` filters).

locals {
  # ===========================================================================
  # Schema
  # ===========================================================================

  # Bucket attributes that can also be set under `defaults`.
  setting_keys = [
    "autoclass", "cors", "data_locations", "default_event_based_hold",
    "deletion_policy", "enable_object_retention", "force_destroy",
    "hierarchical_namespace", "kms_key_name", "labels", "lifecycle_rules",
    "location", "logging", "project_id", "public_access_prevention",
    "requester_pays", "retention_policy", "rpo",
    "soft_delete_retention_seconds", "storage_class",
    "uniform_bucket_level_access", "versioning", "website",
  ]
  bucket_only_keys = ["iam", "name"]
  bucket_keys      = concat(local.bucket_only_keys, local.setting_keys)

  # Used when neither the bucket nor `defaults` sets the attribute.
  builtin_defaults = {
    storage_class               = "STANDARD"
    uniform_bucket_level_access = true
    public_access_prevention    = "enforced"
    force_destroy               = false
    versioning                  = false
  }

  bool_settings = [
    "default_event_based_hold", "enable_object_retention", "force_destroy",
    "hierarchical_namespace", "requester_pays", "uniform_bucket_level_access",
    "versioning",
  ]

  storage_classes           = ["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE", "MULTI_REGIONAL", "REGIONAL"]
  matchable_storage_classes = concat(local.storage_classes, ["DURABLE_REDUCED_AVAILABILITY"])

  # Case-insensitive enumerations; values are normalised to the listed case.
  enum_settings = {
    storage_class            = { values = local.storage_classes, upper = true }
    deletion_policy          = { values = ["DELETE", "PREVENT", "ABANDON"], upper = true }
    public_access_prevention = { values = ["enforced", "inherited"], upper = false }
    rpo                      = { values = ["DEFAULT", "ASYNC_TURBO"], upper = true }
  }

  pattern_settings = {
    project_id   = { pattern = local.re_project_id, expected = "a valid project ID" }
    location     = { pattern = "^[A-Za-z0-9-]+$", expected = "a location such as US, EU or US-CENTRAL1" }
    kms_key_name = { pattern = "^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", expected = "a Cloud KMS key name (projects/P/locations/L/keyRings/R/cryptoKeys/K)" }
  }

  autoclass_keys             = ["enabled", "terminal_storage_class"]
  autoclass_terminal_classes = ["NEARLINE", "ARCHIVE"]
  retention_policy_keys      = ["is_locked", "retention_period"]
  logging_keys               = ["log_bucket", "log_object_prefix"]
  website_keys               = ["main_page_suffix", "not_found_page"]
  cors_keys                  = ["max_age_seconds", "method", "origin", "response_header"]
  cors_list_keys             = ["method", "origin", "response_header"]

  rule_keys        = ["action", "condition"]
  rule_action_keys = ["storage_class", "type"]
  rule_condition_keys = [
    "age", "created_before", "custom_time_before", "days_since_custom_time",
    "days_since_noncurrent_time", "matches_prefix", "matches_storage_class",
    "matches_suffix", "noncurrent_time_before", "num_newer_versions",
    "size_above_bytes", "size_below_bytes", "with_state",
  ]
  rule_number_keys = [
    "age", "days_since_custom_time", "days_since_noncurrent_time",
    "num_newer_versions", "size_above_bytes", "size_below_bytes",
  ]
  rule_date_keys        = ["created_before", "custom_time_before", "noncurrent_time_before"]
  rule_string_list_keys = ["matches_prefix", "matches_suffix"]
  rule_with_states      = ["LIVE", "ARCHIVED", "ANY"]
  rule_action_types = {
    delete                         = "Delete"
    setstorageclass                = "SetStorageClass"
    abortincompletemultipartupload = "AbortIncompleteMultipartUpload"
  }
  abort_upload_condition_keys = ["age", "matches_prefix", "matches_suffix"]

  iam_keys           = ["condition", "domains", "groups", "members", "mode", "role", "service_accounts", "users"]
  iam_condition_keys = ["description", "expression", "title"]
  iam_modes          = ["authoritative", "additive"]
  # Shorthand principal lists and the IAM prefix added to each entry.
  iam_principal_kinds = {
    users            = "user"
    groups           = "group"
    service_accounts = "serviceAccount"
    domains          = "domain"
  }
  public_members = ["allUsers", "allAuthenticatedUsers"]
  member_formats = "user:EMAIL, group:EMAIL, serviceAccount:EMAIL, domain:DOMAIN, allUsers, allAuthenticatedUsers, projectOwner:PROJECT_ID, projectEditor:PROJECT_ID, projectViewer:PROJECT_ID, principal://... or principalSet://..."

  re_email       = "[^@\\s:|]+@[^@\\s:|]+\\.[^@\\s:|]+"
  re_domain      = "(?i:(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63})"
  re_member      = "^(?:(?:user|group|serviceAccount):${local.re_email}|domain:${local.re_domain}|allUsers|allAuthenticatedUsers|project(?:Owner|Editor|Viewer):[a-z0-9][a-z0-9.:-]*|principal(?:Set)?://\\S+)$"
  re_role        = "^(?:roles/[A-Za-z0-9_.]+|(?:projects|organizations)/[A-Za-z0-9_.:-]+/roles/[A-Za-z0-9_.]+)$"
  re_project_id  = "^(?:[a-z0-9.-]+:)?[a-z][a-z0-9-]{4,28}[a-z0-9]$"
  re_label_key   = "^[\\p{Ll}\\p{Lo}][\\p{Ll}\\p{Lo}\\p{N}_-]{0,62}$"
  re_label_value = "^[\\p{Ll}\\p{Lo}\\p{N}_-]{0,63}$"
  re_date        = "^[0-9]{4}-[0-9]{2}-[0-9]{2}$"

  # ===========================================================================
  # Document
  # ===========================================================================

  document        = trimspace(var.yaml) == "" ? null : yamldecode(var.yaml)
  document_is_map = can(keys(local.document))
  top_level_keys  = try(keys(local.document), [])
  unknown_top_level_keys = [
    for k in local.top_level_keys : k
    if !contains(["buckets", "defaults"], k) && !can(regex("^x-", k))
  ]

  raw_defaults    = try(local.document.defaults, null)
  defaults_is_map = can(keys(local.raw_defaults))
  raw_buckets     = try(local.document.buckets, null)
  bucket_items    = try(concat(local.raw_buckets, []), [])

  document_errors = compact([
    local.document != null ? "" : "the configuration is empty; expected a mapping with a 'buckets' list",
    local.document == null || local.document_is_map ? "" : "the configuration must be a mapping with a 'buckets' list",
    !local.document_is_map || contains(local.top_level_keys, "buckets") ? "" : "missing required top-level key 'buckets'",
    local.raw_buckets == null || can(concat(local.raw_buckets, [])) ? "" : "'buckets' must be a list of bucket definitions",
    local.raw_defaults == null || local.defaults_is_map ? "" : "'defaults' must be a mapping of bucket attributes",
    length(local.unknown_top_level_keys) == 0 ? "" : "unknown top-level key(s): ${join(", ", local.unknown_top_level_keys)} (allowed: buckets, defaults and x-* extension keys)",
  ])

  # ===========================================================================
  # Bucket names
  # ===========================================================================

  # Name from the YAML document (the map key), or null when missing/invalid.
  bucket_names = [for b in local.bucket_items : try(tostring(b.name), null)]
  full_names   = [for n in local.bucket_names : n == null ? null : "${var.name_prefix}${n}"]
  bucket_refs  = [for i, n in local.bucket_names : n == null ? "buckets[${i}]" : "bucket ${jsonencode(n)}"]

  name_errors = flatten([
    for i, b in local.bucket_items : [
      for message in(
        !can(keys(b)) ? [] :
        try(b.name, null) == null ? ["'name' is required"] :
        local.bucket_names[i] == null ? ["name must be a string, got ${jsonencode(b.name)}"] :
        [
          can(regex("^[a-z0-9][a-z0-9._-]*[a-z0-9]$", local.full_names[i])) ? "" : "name ${jsonencode(local.full_names[i])} may only contain lowercase letters, digits, dashes, underscores and dots, and must start and end with a letter or digit",
          length(local.full_names[i]) >= 3 && length(local.full_names[i]) <= (can(regex("[.]", local.full_names[i])) ? 222 : 63) ? "" : "name ${jsonencode(local.full_names[i])} must be 3-63 characters long (up to 222 if it contains dots)",
          !can(regex("[.]", local.full_names[i])) || alltrue([for part in split(".", local.full_names[i]) : length(part) >= 1 && length(part) <= 63]) ? "" : "name ${jsonencode(local.full_names[i])} has an empty dot-separated part or one longer than 63 characters",
          !can(regex("^[0-9]{1,3}(?:[.][0-9]{1,3}){3}$", local.full_names[i])) ? "" : "name ${jsonencode(local.full_names[i])} cannot be an IP address",
          !can(regex("^goog", local.full_names[i])) ? "" : "name ${jsonencode(local.full_names[i])} cannot start with \"goog\"",
          !can(regex("g[o0][o0]gle", local.full_names[i])) ? "" : "name ${jsonencode(local.full_names[i])} cannot contain \"google\" or a close misspelling of it",
        ]
      ) : "${local.bucket_refs[i]}: ${message}" if message != ""
    ]
  ])

  bucket_indexes_by_name = { for i, n in local.bucket_names : n => i... if n != null }
  duplicate_name_errors = [
    for n, indexes in local.bucket_indexes_by_name :
    "bucket ${jsonencode(n)}: defined more than once (${join(", ", [for i in indexes : "buckets[${i}]"])})"
    if length(indexes) > 1
  ]

  # ===========================================================================
  # Attribute checks, run where each value is written: under `defaults` and on
  # every bucket entry. `v` holds every known attribute (null when absent).
  # ===========================================================================

  targets = [
    for t in concat(
      [for d in [local.raw_defaults] : { ref = "defaults", obj = d, is_bucket = false } if local.defaults_is_map],
      [for i, b in local.bucket_items : { ref = local.bucket_refs[i], obj = b, is_bucket = true }],
      ) : {
      ref       = t.ref
      is_bucket = t.is_bucket
      is_map    = can(keys(t.obj))
      keys      = try(keys(t.obj), [])
      v         = { for k in local.bucket_keys : k => try(t.obj[k], null) }
    }
  ]

  target_errors = flatten([
    for t in local.targets : [
      for message in concat(
        [
          t.is_map ? "" : "must be a mapping of bucket attributes",
          length(setsubtract(t.keys, local.bucket_keys)) == 0 ? "" : "unknown attribute(s): ${join(", ", sort(setsubtract(t.keys, local.bucket_keys)))}",
        ],
        [for k in local.bucket_only_keys : "${k} can only be set on individual buckets" if !t.is_bucket && contains(t.keys, k)],
        [for k in local.bool_settings : "${k} must be true or false, got ${jsonencode(t.v[k])}" if !can(tobool(t.v[k]))],
        [
          for k, spec in local.enum_settings : "${k} must be one of ${join(", ", spec.values)}, got ${jsonencode(t.v[k])}"
          if t.v[k] != null && !try(contains(spec.values, spec.upper ? upper(t.v[k]) : lower(t.v[k])), false)
        ],
        [
          for k, spec in local.pattern_settings : "${k} must be ${spec.expected}, got ${jsonencode(t.v[k])}"
          if t.v[k] != null && !can(regex(spec.pattern, t.v[k]))
        ],
        [
          t.v.soft_delete_retention_seconds == null || try(
            floor(tonumber(t.v.soft_delete_retention_seconds)) == tonumber(t.v.soft_delete_retention_seconds) && (
              tonumber(t.v.soft_delete_retention_seconds) == 0 || (
                tonumber(t.v.soft_delete_retention_seconds) >= 604800 && tonumber(t.v.soft_delete_retention_seconds) <= 7776000
              )
            ),
            false
          ) ? "" : "soft_delete_retention_seconds must be 0 (disabled) or a whole number between 604800 (7 days) and 7776000 (90 days), got ${jsonencode(t.v.soft_delete_retention_seconds)}",
          t.v.data_locations == null || try(
            length(concat(t.v.data_locations, [])) > 0 && alltrue([for l in t.v.data_locations : can(regex("^[A-Za-z0-9-]+$", l))]),
            false
          ) ? "" : "data_locations must be a non-empty list of region names, got ${jsonencode(t.v.data_locations)}",
          # --- labels ------------------------------------------------------------
          t.v.labels == null || can(keys(t.v.labels)) ? "" : "labels must be a mapping of key: value pairs, got ${jsonencode(t.v.labels)}",
          # --- autoclass ---------------------------------------------------------
          t.v.autoclass == null || can(tobool(t.v.autoclass)) || can(keys(t.v.autoclass)) ? "" : "autoclass must be true, false or a mapping with enabled and terminal_storage_class, got ${jsonencode(t.v.autoclass)}",
          length(setsubtract(try(keys(t.v.autoclass), []), local.autoclass_keys)) == 0 ? "" : "unknown attribute(s) in autoclass: ${join(", ", sort(setsubtract(try(keys(t.v.autoclass), []), local.autoclass_keys)))}",
          can(tobool(try(t.v.autoclass.enabled, null))) ? "" : "autoclass.enabled must be true or false, got ${jsonencode(t.v.autoclass.enabled)}",
          try(t.v.autoclass.terminal_storage_class, null) == null || try(contains(local.autoclass_terminal_classes, upper(t.v.autoclass.terminal_storage_class)), false) ? "" : "autoclass.terminal_storage_class must be one of ${join(", ", local.autoclass_terminal_classes)}, got ${jsonencode(t.v.autoclass.terminal_storage_class)}",
          # --- retention_policy --------------------------------------------------
          t.v.retention_policy == null || can(keys(t.v.retention_policy)) ? "" : "retention_policy must be a mapping with retention_period and optional is_locked, got ${jsonencode(t.v.retention_policy)}",
          length(setsubtract(try(keys(t.v.retention_policy), []), local.retention_policy_keys)) == 0 ? "" : "unknown attribute(s) in retention_policy: ${join(", ", sort(setsubtract(try(keys(t.v.retention_policy), []), local.retention_policy_keys)))}",
          !can(keys(t.v.retention_policy)) || try(t.v.retention_policy.retention_period, null) != null ? "" : "retention_policy.retention_period is required",
          try(t.v.retention_policy.retention_period, null) == null || try(
            floor(tonumber(t.v.retention_policy.retention_period)) == tonumber(t.v.retention_policy.retention_period) &&
            tonumber(t.v.retention_policy.retention_period) >= 1 && tonumber(t.v.retention_policy.retention_period) <= 3155760000,
            false
          ) ? "" : "retention_policy.retention_period must be a whole number of seconds between 1 and 3155760000, got ${jsonencode(t.v.retention_policy.retention_period)}",
          can(tobool(try(t.v.retention_policy.is_locked, null))) ? "" : "retention_policy.is_locked must be true or false, got ${jsonencode(t.v.retention_policy.is_locked)}",
          # --- logging -----------------------------------------------------------
          t.v.logging == null || can(keys(t.v.logging)) ? "" : "logging must be a mapping with log_bucket and optional log_object_prefix, got ${jsonencode(t.v.logging)}",
          length(setsubtract(try(keys(t.v.logging), []), local.logging_keys)) == 0 ? "" : "unknown attribute(s) in logging: ${join(", ", sort(setsubtract(try(keys(t.v.logging), []), local.logging_keys)))}",
          !can(keys(t.v.logging)) || try(length(tostring(t.v.logging.log_bucket)) > 0, false) ? "" : "logging.log_bucket is required",
          can(tostring(try(t.v.logging.log_object_prefix, null))) ? "" : "logging.log_object_prefix must be a string",
          # --- website -----------------------------------------------------------
          t.v.website == null || can(keys(t.v.website)) ? "" : "website must be a mapping with main_page_suffix and/or not_found_page, got ${jsonencode(t.v.website)}",
          length(setsubtract(try(keys(t.v.website), []), local.website_keys)) == 0 ? "" : "unknown attribute(s) in website: ${join(", ", sort(setsubtract(try(keys(t.v.website), []), local.website_keys)))}",
          can(tostring(try(t.v.website.main_page_suffix, null))) ? "" : "website.main_page_suffix must be a string",
          can(tostring(try(t.v.website.not_found_page, null))) ? "" : "website.not_found_page must be a string",
          # --- lists (their items are checked below) -----------------------------
          t.v.cors == null || can(concat(t.v.cors, [])) ? "" : "cors must be a list of CORS rules, got ${jsonencode(t.v.cors)}",
          t.v.lifecycle_rules == null || can(concat(t.v.lifecycle_rules, [])) ? "" : "lifecycle_rules must be a list of rules, got ${jsonencode(t.v.lifecycle_rules)}",
          length(try(concat(t.v.lifecycle_rules, []), [])) <= 100 ? "" : "at most 100 lifecycle_rules are allowed, got ${length(try(concat(t.v.lifecycle_rules, []), []))}",
          !t.is_bucket || t.v.iam == null || can(concat(t.v.iam, [])) ? "" : "iam must be a list of role bindings, got ${jsonencode(t.v.iam)}",
        ],
        [
          for k in try(keys(t.v.labels), []) : "label key ${jsonencode(k)} is invalid (use lowercase letters, digits, '_' and '-', start with a letter, at most 63 characters)"
          if !can(regex(local.re_label_key, k))
        ],
        [
          for k in try(keys(t.v.labels), []) : "label ${jsonencode(k)} has an invalid value ${jsonencode(t.v.labels[k])} (use lowercase letters, digits, '_' and '-', at most 63 characters)"
          if !can(regex(local.re_label_value, t.v.labels[k]))
        ],
      ) : "${t.ref}: ${message}" if message != ""
    ]
  ])

  # --- CORS rules --------------------------------------------------------------

  cors_items = flatten([
    for t in local.targets : [
      for i, c in try(concat(t.v.cors, []), []) : { ref = "${t.ref}: cors[${i}]", obj = c }
    ]
  ])

  cors_errors = flatten([
    for c in local.cors_items : [
      for message in concat(
        [
          try(length(keys(c.obj)) > 0, false) ? "" : "must be a non-empty mapping with origin, method, response_header and/or max_age_seconds",
          length(setsubtract(try(keys(c.obj), []), local.cors_keys)) == 0 ? "" : "unknown attribute(s): ${join(", ", sort(setsubtract(try(keys(c.obj), []), local.cors_keys)))}",
          try(c.obj.max_age_seconds, null) == null || try(
            tonumber(c.obj.max_age_seconds) >= 0 && floor(tonumber(c.obj.max_age_seconds)) == tonumber(c.obj.max_age_seconds),
            false
          ) ? "" : "max_age_seconds must be a non-negative whole number, got ${jsonencode(c.obj.max_age_seconds)}",
        ],
        [
          for k in local.cors_list_keys : "${k} must be a list of strings, got ${jsonencode(c.obj[k])}"
          if try(c.obj[k], null) != null && !try(alltrue([for s in concat(c.obj[k], []) : s != null && can(tostring(s))]), false)
        ],
      ) : "${c.ref}: ${message}" if message != ""
    ]
  ])

  # --- Lifecycle rules ---------------------------------------------------------

  rule_items = flatten([
    for t in local.targets : [
      for i, r in try(concat(t.v.lifecycle_rules, []), []) : {
        ref       = "${t.ref}: lifecycle_rules[${i}]"
        is_map    = can(keys(r))
        keys      = try(keys(r), [])
        action    = try(r.action, null)
        condition = try(r.condition, null)
        # Canonical action type, or null when missing or unknown.
        type = try(local.rule_action_types[lower(r.action.type)], null)
        # Condition criteria that are set (non-null).
        criteria = try([for k, v in r.condition : k if v != null], [])
      }
    ]
  ])

  rule_errors = flatten([
    for r in local.rule_items : [
      for message in concat(
        [
          r.is_map ? "" : "must be a mapping with action and condition",
          length(setsubtract(r.keys, local.rule_keys)) == 0 ? "" : "unknown attribute(s): ${join(", ", sort(setsubtract(r.keys, local.rule_keys)))}",
          !r.is_map || r.action != null ? "" : "action is required",
          r.action == null || can(keys(r.action)) ? "" : "action must be a mapping with type and optional storage_class, got ${jsonencode(r.action)}",
          length(setsubtract(try(keys(r.action), []), local.rule_action_keys)) == 0 ? "" : "unknown attribute(s) in action: ${join(", ", sort(setsubtract(try(keys(r.action), []), local.rule_action_keys)))}",
          !can(keys(r.action)) || r.type != null ? "" : "action.type must be one of Delete, SetStorageClass, AbortIncompleteMultipartUpload, got ${jsonencode(try(r.action.type, null))}",
          r.type != "SetStorageClass" || try(contains(local.storage_classes, upper(r.action.storage_class)), false) ? "" : "action.storage_class must be one of ${join(", ", local.storage_classes)} for SetStorageClass, got ${jsonencode(try(r.action.storage_class, null))}",
          r.type == "SetStorageClass" || try(r.action.storage_class, null) == null ? "" : "action.storage_class is only allowed with the SetStorageClass action",
          !r.is_map || r.condition != null ? "" : "condition is required",
          r.condition == null || can(keys(r.condition)) ? "" : "condition must be a mapping of criteria, got ${jsonencode(r.condition)}",
          length(setsubtract(try(keys(r.condition), []), local.rule_condition_keys)) == 0 ? "" : "unknown attribute(s) in condition: ${join(", ", sort(setsubtract(try(keys(r.condition), []), local.rule_condition_keys)))}",
          !can(keys(r.condition)) || length(r.criteria) > 0 ? "" : "condition must set at least one criterion",
          r.type != "AbortIncompleteMultipartUpload" || length(setsubtract(r.criteria, local.abort_upload_condition_keys)) == 0 ? "" : "AbortIncompleteMultipartUpload rules only support the age, matches_prefix and matches_suffix conditions",
          try(r.condition.with_state, null) == null || try(contains(local.rule_with_states, upper(r.condition.with_state)), false) ? "" : "condition.with_state must be one of ${join(", ", local.rule_with_states)}, got ${jsonencode(r.condition.with_state)}",
          try(r.condition.matches_storage_class, null) == null || try(
            length(concat(r.condition.matches_storage_class, [])) > 0 && alltrue([for s in r.condition.matches_storage_class : contains(local.matchable_storage_classes, upper(s))]),
            false
          ) ? "" : "condition.matches_storage_class must be a non-empty list of ${join(", ", local.matchable_storage_classes)}, got ${jsonencode(r.condition.matches_storage_class)}",
        ],
        [
          for k in local.rule_number_keys : "condition.${k} must be a non-negative whole number, got ${jsonencode(r.condition[k])}"
          if try(r.condition[k], null) != null && !try(tonumber(r.condition[k]) >= 0 && floor(tonumber(r.condition[k])) == tonumber(r.condition[k]), false)
        ],
        [
          # Unquoted YAML dates decode as timestamps ("2024-01-01T00:00:00Z").
          for k in local.rule_date_keys : "condition.${k} must be a date in YYYY-MM-DD format, got ${jsonencode(r.condition[k])}"
          if try(r.condition[k], null) != null && !can(regex(local.re_date, replace(r.condition[k], "/T00:00:00Z$/", "")))
        ],
        [
          for k in local.rule_string_list_keys : "condition.${k} must be a list of strings, got ${jsonencode(r.condition[k])}"
          if try(r.condition[k], null) != null && !try(alltrue([for s in concat(r.condition[k], []) : s != null && can(tostring(s))]), false)
        ],
      ) : "${r.ref}: ${message}" if message != ""
    ]
  ])

  # ===========================================================================
  # Effective settings per bucket: bucket value > `defaults` > built-in
  # default. A key that is present wins even when its value is null, which
  # lets a bucket unset a default and fall back to the provider/GCP default.
  # ===========================================================================

  effective = [
    for b in local.bucket_items : {
      for k in local.setting_keys : k => try(b[k], local.raw_defaults[k], local.builtin_defaults[k], null)
    }
  ]

  autoclass_on = [
    for e in local.effective : (
      can(keys(e.autoclass)) ? try(tobool(e.autoclass.enabled), null) != false : try(tobool(e.autoclass), false) == true
    )
  ]
  hns_on = [for e in local.effective : try(tobool(e.hierarchical_namespace), false) == true]

  # Labels merge instead of replacing: var.labels < defaults < bucket. Values
  # are converted one by one: tomap() would fail on a map that mixes numbers
  # and booleans (no common type) and silently drop it.
  yaml_labels = [
    for b in local.bucket_items : merge(
      try({ for k, v in local.raw_defaults.labels : k => tostring(v) }, {}),
      try({ for k, v in b.labels : k => tostring(v) }, {}),
    )
  ]
  effective_labels = [for labels in local.yaml_labels : merge(var.labels, labels)]

  bucket_errors = flatten([
    for i, e in local.effective : [
      for message in [
        e.location != null ? "" : "location is required (set it on the bucket or under defaults)",
        # var.labels is left out so an unknown-at-plan value can't block planning.
        length(local.yaml_labels[i]) <= 64 ? "" : "at most 64 labels are allowed, got ${length(local.yaml_labels[i])} (including labels inherited from defaults)",
        !local.autoclass_on[i] || try(upper(e.storage_class), "STANDARD") == "STANDARD" ? "" : "storage_class must be STANDARD when autoclass is enabled",
        !local.autoclass_on[i] || !anytrue([for r in try(concat(e.lifecycle_rules, []), []) : try(lower(r.action.type), "") == "setstorageclass"]) ? "" : "autoclass cannot be combined with lifecycle rules that use the SetStorageClass action",
        !local.autoclass_on[i] || !anytrue([for r in try(concat(e.lifecycle_rules, []), []) : try(r.condition.matches_storage_class, null) != null]) ? "" : "autoclass cannot be combined with lifecycle rules that use the matches_storage_class condition",
        !local.hns_on[i] || try(tobool(e.uniform_bucket_level_access), false) == true ? "" : "hierarchical_namespace requires uniform_bucket_level_access: true",
        !local.hns_on[i] || try(tobool(e.versioning), false) != true ? "" : "hierarchical_namespace cannot be combined with versioning",
        !local.hns_on[i] || e.retention_policy == null ? "" : "hierarchical_namespace cannot be combined with retention_policy",
        !local.hns_on[i] || try(tobool(e.enable_object_retention), false) != true ? "" : "hierarchical_namespace cannot be combined with enable_object_retention",
        !local.hns_on[i] || try(tobool(e.default_event_based_hold), false) != true ? "" : "hierarchical_namespace cannot be combined with default_event_based_hold",
      ] : "${local.bucket_refs[i]}: ${message}" if message != "" && can(keys(local.bucket_items[i]))
    ]
  ])

  # ===========================================================================
  # IAM
  # ===========================================================================

  iam_items = flatten([
    for bi, b in local.bucket_items : [
      for ii, x in try(concat(b.iam, []), []) : {
        bucket_index = bi
        bucket       = local.bucket_names[bi]
        index        = ii
        ref          = "${local.bucket_refs[bi]}: iam[${ii}]${try(" (${tostring(x.role)})", "")}"
        is_map       = can(keys(x))
        keys         = try(keys(x), [])
        role         = try(tostring(x.role), null)
        mode_raw     = try(x.mode, null)
        mode         = try(lower(x.mode), "authoritative")
        condition    = try(x.condition, null)
        lists        = { for k in concat(["members"], keys(local.iam_principal_kinds)) : k => try(x[k], null) }
        principals = concat(
          [for m in try(concat(x.members, []), []) : { source = "members", value = m }],
          flatten([
            for kind in keys(local.iam_principal_kinds) : [
              for m in try(concat(x[kind], []), []) : { source = kind, value = m }
            ]
          ]),
        )
      }
    ]
  ])

  iam_parsed = [
    for x in local.iam_items : merge(x, {
      condition_title = try(tostring(x.condition.title), "")
      # Emails and domains are case-insensitive in IAM: lower-case them so the
      # same principal written twice collapses into one member.
      members = try(sort(distinct([
        for p in x.principals : (
          p.source != "members" ? "${local.iam_principal_kinds[p.source]}:${lower(p.value)}" :
          can(regex("^(?:user|group|serviceAccount|domain):", p.value)) ? "${regex("^(?:user|group|serviceAccount|domain):", p.value)}${lower(replace(p.value, "/^(?:user|group|serviceAccount|domain):/", ""))}" :
          p.value
        )
      ])), [])
      condition_normalized = x.condition == null ? null : {
        title       = try(tostring(x.condition.title), null)
        description = try(tostring(x.condition.description), null)
        expression  = try(tostring(x.condition.expression), null)
      }
      # Resource key: one authoritative binding per bucket/role/condition.
      key = try("${x.bucket}|${x.role}${x.condition == null ? "" : "|${tostring(x.condition.title)}"}", null)
      # Uniqueness key: like `key`, but by entry index so duplicate bucket
      # names don't also report IAM duplicates.
      unique_key = try("${x.bucket_index}|${x.role}${x.condition == null ? "" : "|${tostring(x.condition.title)}"}", null)
    })
  ]

  iam_errors = flatten([
    for x in local.iam_parsed : [
      for message in concat(
        [
          x.is_map ? "" : "must be a mapping with role and principals",
          length(setsubtract(x.keys, local.iam_keys)) == 0 ? "" : "unknown attribute(s): ${join(", ", sort(setsubtract(x.keys, local.iam_keys)))}",
          !x.is_map || x.role != null ? "" : "role is required",
          x.role == null || can(regex(local.re_role, x.role)) ? "" : "role must look like roles/NAME, projects/PROJECT/roles/NAME or organizations/ORG/roles/NAME, got ${jsonencode(x.role)}",
          x.mode_raw == null || contains(local.iam_modes, x.mode) ? "" : "mode must be one of ${join(", ", local.iam_modes)}, got ${jsonencode(x.mode_raw)}",
          !x.is_map || length(x.principals) > 0 ? "" : "at least one principal is required (members, users, groups, service_accounts or domains)",
        ],
        [for k, v in x.lists : "${k} must be a list, got ${jsonencode(v)}" if v != null && !can(concat(v, []))],
        [
          for p in x.principals : "invalid member ${jsonencode(p.value)} (expected ${local.member_formats})"
          if p.source == "members" && !can(regex(local.re_member, p.value))
        ],
        [
          for p in x.principals : "invalid email ${jsonencode(p.value)} in ${p.source} (use a bare address such as name@example.com; the ${local.iam_principal_kinds[p.source]}: prefix is added automatically)"
          if contains(["users", "groups", "service_accounts"], p.source) && !can(regex("^${local.re_email}$", p.value))
        ],
        [
          for p in x.principals : "invalid domain ${jsonencode(p.value)} in domains (expected a domain such as example.com)"
          if p.source == "domains" && !can(regex("^${local.re_domain}$", p.value))
        ],
        [
          # No "got" here: jsonencode() would mangle the < and > of CEL expressions.
          x.condition == null || can(keys(x.condition)) ? "" : "condition must be a mapping with title, expression and optional description",
          length(setsubtract(try(keys(x.condition), []), local.iam_condition_keys)) == 0 ? "" : "unknown attribute(s) in condition: ${join(", ", sort(setsubtract(try(keys(x.condition), []), local.iam_condition_keys)))}",
          !can(keys(x.condition)) || try(length(tostring(x.condition.title)) > 0, false) ? "" : "condition.title is required",
          !can(keys(x.condition)) || try(length(tostring(x.condition.expression)) > 0, false) ? "" : "condition.expression is required",
          can(tostring(try(x.condition.description, null))) ? "" : "condition.description must be a string",
          x.condition == null || try(tobool(local.effective[x.bucket_index].uniform_bucket_level_access), false) == true ? "" : "IAM conditions require uniform_bucket_level_access: true",
          length(setintersection(x.members, local.public_members)) == 0 || try(lower(local.effective[x.bucket_index].public_access_prevention), "") != "enforced" ? "" : "allUsers and allAuthenticatedUsers cannot be granted while public_access_prevention is enforced; set public_access_prevention: inherited on this bucket",
        ],
      ) : "${x.ref}: ${message}" if message != ""
    ]
  ])

  iam_entries_by_unique_key = {
    for x in local.iam_parsed : x.unique_key => {
      index      = x.index
      bucket_ref = local.bucket_refs[x.bucket_index]
      role       = x.role
      title      = x.condition == null ? "" : x.condition_title
    }... if x.unique_key != null
  }
  iam_duplicate_errors = [
    for key, entries in local.iam_entries_by_unique_key :
    "${entries[0].bucket_ref}: role ${entries[0].role}${entries[0].title == "" ? "" : " with condition \"${entries[0].title}\""} is bound in more than one iam entry (${join(", ", [for e in entries : "iam[${e.index}]"])}); merge them, or give each condition a distinct title"
    if length(entries) > 1
  ]

  # ===========================================================================
  # Result
  # ===========================================================================

  errors = concat(
    local.document_errors,
    sort(distinct(concat(
      local.name_errors,
      local.duplicate_name_errors,
      local.target_errors,
      local.cors_errors,
      local.rule_errors,
      local.bucket_errors,
      local.iam_errors,
      local.iam_duplicate_errors,
    ))),
  )
  valid = length(local.errors) == 0

  buckets = {
    for i, e in local.effective : local.bucket_names[i] => {
      name                          = local.full_names[i]
      project_id                    = e.project_id == null ? var.project_id : tostring(e.project_id)
      location                      = upper(e.location)
      storage_class                 = e.storage_class == null ? null : upper(e.storage_class)
      labels                        = local.effective_labels[i]
      force_destroy                 = tobool(e.force_destroy)
      deletion_policy               = e.deletion_policy == null ? null : upper(e.deletion_policy)
      uniform_bucket_level_access   = tobool(e.uniform_bucket_level_access)
      public_access_prevention      = e.public_access_prevention == null ? null : lower(e.public_access_prevention)
      versioning                    = tobool(e.versioning)
      requester_pays                = tobool(e.requester_pays)
      default_event_based_hold      = tobool(e.default_event_based_hold)
      enable_object_retention       = tobool(e.enable_object_retention)
      hierarchical_namespace        = tobool(e.hierarchical_namespace)
      rpo                           = e.rpo == null ? null : upper(e.rpo)
      kms_key_name                  = e.kms_key_name == null ? null : tostring(e.kms_key_name)
      soft_delete_retention_seconds = e.soft_delete_retention_seconds == null ? null : tonumber(e.soft_delete_retention_seconds)
      data_locations                = e.data_locations == null ? null : [for l in e.data_locations : upper(l)]
      autoclass = e.autoclass == null ? null : {
        enabled                = local.autoclass_on[i]
        terminal_storage_class = try(upper(e.autoclass.terminal_storage_class), null)
      }
      retention_policy = e.retention_policy == null ? null : {
        retention_period = tostring(tonumber(e.retention_policy.retention_period))
        is_locked        = try(tobool(e.retention_policy.is_locked), null)
      }
      logging = e.logging == null ? null : {
        log_bucket        = tostring(e.logging.log_bucket)
        log_object_prefix = try(tostring(e.logging.log_object_prefix), null)
      }
      website = e.website == null ? null : {
        main_page_suffix = try(tostring(e.website.main_page_suffix), null)
        not_found_page   = try(tostring(e.website.not_found_page), null)
      }
      cors = [
        for c in try(concat(e.cors, []), []) : {
          origin          = try([for v in c.origin : tostring(v)], null)
          method          = try([for v in c.method : tostring(v)], null)
          response_header = try([for v in c.response_header : tostring(v)], null)
          max_age_seconds = try(tonumber(c.max_age_seconds), null)
        }
      ]
      lifecycle_rules = [
        for r in try(concat(e.lifecycle_rules, []), []) : {
          action_type                = local.rule_action_types[lower(r.action.type)]
          action_storage_class       = try(upper(r.action.storage_class), null)
          age                        = try(tonumber(r.condition.age), null)
          created_before             = try(replace(r.condition.created_before, "/T00:00:00Z$/", ""), null)
          custom_time_before         = try(replace(r.condition.custom_time_before, "/T00:00:00Z$/", ""), null)
          noncurrent_time_before     = try(replace(r.condition.noncurrent_time_before, "/T00:00:00Z$/", ""), null)
          days_since_custom_time     = try(tonumber(r.condition.days_since_custom_time), null)
          days_since_noncurrent_time = try(tonumber(r.condition.days_since_noncurrent_time), null)
          num_newer_versions         = try(tonumber(r.condition.num_newer_versions), null)
          size_above_bytes           = try(tonumber(r.condition.size_above_bytes), null)
          size_below_bytes           = try(tonumber(r.condition.size_below_bytes), null)
          with_state                 = try(upper(r.condition.with_state), null)
          matches_storage_class      = try([for s in r.condition.matches_storage_class : upper(s)], null)
          matches_prefix             = try([for s in r.condition.matches_prefix : tostring(s)], null)
          matches_suffix             = try([for s in r.condition.matches_suffix : tostring(s)], null)
          # The provider drops zero values unless told to send them.
          send_age_if_zero                        = try(tonumber(r.condition.age) == 0, false)
          send_days_since_custom_time_if_zero     = try(tonumber(r.condition.days_since_custom_time) == 0, false)
          send_days_since_noncurrent_time_if_zero = try(tonumber(r.condition.days_since_noncurrent_time) == 0, false)
          send_num_newer_versions_if_zero         = try(tonumber(r.condition.num_newer_versions) == 0, false)
        }
      ]
    } if local.valid
  }

  iam_bindings = {
    for x in local.iam_parsed : x.key => {
      bucket    = x.bucket
      role      = x.role
      members   = x.members
      condition = x.condition_normalized
    } if local.valid && x.mode == "authoritative"
  }

  iam_members = {
    for m in flatten([
      for x in local.iam_parsed : [
        for member in x.members : {
          key       = try("${x.key}|${member}", null)
          bucket    = x.bucket
          role      = x.role
          member    = member
          condition = x.condition_normalized
        }
      ] if x.mode == "additive"
      ]) : m.key => {
      bucket    = m.bucket
      role      = m.role
      member    = m.member
      condition = m.condition
    } if local.valid
  }
}
