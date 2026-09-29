# GCS buckets from YAML: Terraform module

A Terraform module that creates Google Cloud Storage buckets and their IAM role
bindings from a single YAML file. One file can declare any number of buckets,
each with its own settings, lifecycle rules and role bindings for any kind of
IAM principal (users, groups, service accounts, domains, public access,
project convenience values, workload/workforce identity).

The YAML is validated before anything is planned: every mistake in the file is
reported in one plan error, and an invalid file creates nothing.

- Terraform `>= 1.2.0` (verified on 1.2.7, 1.3.0 and 1.16.4)
- Google provider `>= 7.38.0, < 9.0.0` (verified on 7.38.0 and 8.4.0; 7.38.0 is
  the first release with the lifecycle `size_*_bytes` conditions)
- Running the test suite needs Terraform `>= 1.7` (mock providers)

## Quick start

```hcl
module "gcs" {
  source = "git::https://github.com/dsbip/terraform-google-gcs-buckets.git?ref=main"

  config_file = "${path.module}/buckets.yaml"
  project_id  = "my-project" # used when the YAML sets no project_id
}
```

```yaml
# buckets.yaml
defaults:
  location: US-CENTRAL1
  labels:
    managed-by: terraform

buckets:
  - name: acme-app-uploads
    versioning: true
    iam:
      - role: roles/storage.objectViewer
        groups: [app-readers@example.com]
      - role: roles/storage.objectCreator
        members:
          - serviceAccount:uploader@my-project.iam.gserviceaccount.com

  - name: acme-app-exports
    storage_class: NEARLINE
    lifecycle_rules:
      - action: {type: Delete}
        condition: {age: 30}
```

Unless the YAML says otherwise, every bucket gets STANDARD storage, uniform
bucket-level access, public access prevention `enforced`, versioning off and
`force_destroy` off.

## Repository layout

```
.
├── main.tf                 # buckets + IAM resources, built from module.config
├── variables.tf            # config_file, config_vars, project_id, name_prefix, labels
├── outputs.tf              # buckets (carries the validation precondition), names, URLs, IAM
├── versions.tf             # Terraform / provider constraints
├── modules/config/         # YAML parser, validator and normaliser (no resources, no providers)
├── examples/               # runnable root modules, each with its own buckets.yaml
│   ├── basic/              #   two buckets, shorthand IAM
│   ├── complete/           #   every option and every principal kind
│   ├── data-lake/          #   landing/bronze/silver/gold/archive, YAML anchors for shared IAM
│   ├── static-website/     #   public site (allUsers) + CI deploys through workload identity
│   └── multi-environment/  #   one templated file for dev and prod (config_vars + name_prefix)
├── tests/                  # `terraform test` suites (offline) + fixtures
│   └── integration/        # opt-in live test against a real project
└── .tflint.hcl
```

## How it works

1. `main.tf` renders `config_file` with `templatefile(config_file, config_vars)`
   and passes the text to `modules/config`.
2. `modules/config` decodes the YAML and checks it against the schema below. It
   collects every problem into `errors` (it never fails on its own), applies
   defaults and returns consistently typed maps: `buckets`, `iam_bindings`
   (authoritative) and `iam_members` (additive). When there is any error those
   maps are empty.
3. The root module creates `google_storage_bucket.this`,
   `google_storage_bucket_iam_binding.this` and
   `google_storage_bucket_iam_member.this` from those maps.
4. A precondition on `output.buckets` turns a non-empty `errors` list into a
   plan error that lists every problem. It fires even when the caller doesn't
   use that output. Because the maps are empty, nothing else is planned.

Resource addresses depend only on names, never on list positions, so
reordering buckets, IAM entries or members in the YAML changes nothing:

| Resource | Key |
|---|---|
| `google_storage_bucket.this` | `<name>` (as written in the YAML, without `name_prefix`) |
| `google_storage_bucket_iam_binding.this` | `<name>\|<role>` or `<name>\|<role>\|<condition title>` |
| `google_storage_bucket_iam_member.this` | `<binding key>\|<member>` |

## Module interface

### Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `config_file` | `string` | (required) | Path to the YAML file. Relative paths are resolved from the directory Terraform runs in, so pass `"${path.module}/buckets.yaml"`. Must exist (validated). |
| `config_vars` | `any` (map/object) | `{}` | Variables for the YAML file, which is always rendered with `templatefile()`. See [Templating](#templating). |
| `project_id` | `string` | `null` | Project for buckets whose YAML sets no `project_id` (neither on the bucket nor under `defaults`). If this is null too, the provider's project is used. |
| `name_prefix` | `string` | `""` | Prepended to every bucket name, e.g. `acme-prod-`. Keys and outputs still use the names from the YAML. Lowercase letters, digits, `-`, `_`, `.` (validated). |
| `labels` | `map(string)` | `{}` | Labels applied to every bucket. YAML labels win on key collisions. Validated against the GCP label rules. |

Every input must be known at plan time (for example, don't pass a
`config_vars` value computed by a resource in the same apply): the YAML
decides which resources exist.

### Outputs

| Name | Description |
|---|---|
| `buckets` | Map of YAML name → `{name, id, url, self_link, project, location, storage_class}`. Carries the validation precondition. |
| `bucket_names` | Map of YAML name → actual bucket name (with `name_prefix`). |
| `bucket_urls` | Map of YAML name → `gs://` URL. |
| `iam_bindings` | Map of binding key → `{bucket, role, members, condition}` (authoritative bindings; `condition` is the title or null). |
| `iam_members` | Map of member key → `{bucket, role, member, condition}` (additive grants). |

## YAML reference

### Top level

```yaml
defaults: {...}      # optional: settings inherited by every bucket
buckets: [...]       # required: list of bucket definitions (may be empty)
x-anything: ...      # optional: ignored; a place for YAML anchors
```

Any other top-level key is an error. `buckets:` with no entries (e.g. all of
them commented out) is valid and creates nothing.

### Precedence

For each attribute, the first of these that is present wins:

1. the attribute on the bucket
2. the attribute under `defaults`
3. the module default (see the table below)

- A key that is present wins even when its value is null (`~` or empty). Use
  this to unset a default for one bucket and leave the attribute to
  GCP/provider defaults (e.g. `kms_key_name: ~` for Google-managed
  encryption when `defaults` sets a CMEK key).
- `labels` are merged instead of replaced: `var.labels` < `defaults.labels` <
  bucket `labels`.
- `lifecycle_rules` and `cors` are replaced as a whole: `lifecycle_rules: []`
  on a bucket opts it out of the rules in `defaults`.
- `project_id`: bucket → `defaults` → the `project_id` input → provider
  project.
- `name` and `iam` can only be set on buckets.

### Bucket attributes

| Key | Type / values | Module default | Notes |
|---|---|---|---|
| `name` | string | required | Final name is `name_prefix + name`; must follow the [bucket naming rules](https://cloud.google.com/storage/docs/buckets#naming). Bucket only. |
| `iam` | list of IAM entries | none | See [IAM](#iam). Bucket only. |
| `project_id` | string | `project_id` input | Changing it replaces the bucket. |
| `location` | string | required (bucket or `defaults`) | `US`, `EU`, `ASIA`, a region (`us-central1`) or dual-region (`NAM4`). Upper-cased. |
| `storage_class` | `STANDARD`, `NEARLINE`, `COLDLINE`, `ARCHIVE`, `MULTI_REGIONAL`, `REGIONAL` | `STANDARD` | Case-insensitive. |
| `labels` | map | none | Keys: lowercase letter first, then lowercase letters, digits, `_`, `-` (≤ 63). Values: same characters (≤ 63). At most 64 per bucket after merging. Numbers/booleans are converted to strings. |
| `force_destroy` | bool | `false` | Delete all objects when the bucket is destroyed. |
| `deletion_policy` | `DELETE`, `PREVENT`, `ABANDON` | provider default (`DELETE`) | `PREVENT` makes Terraform refuse to destroy (or replace) the bucket. `ABANDON` forgets it without deleting. |
| `uniform_bucket_level_access` | bool | `true` | Required for IAM conditions and hierarchical namespace. |
| `public_access_prevention` | `enforced`, `inherited` | `enforced` | Must be `inherited` to grant `allUsers`/`allAuthenticatedUsers`. |
| `versioning` | bool | `false` | |
| `requester_pays` | bool | unset | |
| `default_event_based_hold` | bool | unset | |
| `enable_object_retention` | bool | unset | Only settable at creation; changing it replaces the bucket. |
| `hierarchical_namespace` | bool | unset | Only settable at creation; needs uniform bucket-level access; incompatible with versioning, `retention_policy`, `enable_object_retention` and `default_event_based_hold`. |
| `rpo` | `DEFAULT`, `ASYNC_TURBO` | unset | Turbo replication, dual-regions only. |
| `kms_key_name` | `projects/P/locations/L/keyRings/R/cryptoKeys/K` | unset | Default CMEK key (`encryption.default_kms_key_name`). |
| `soft_delete_retention_seconds` | `0` or `604800`–`7776000` | GCS default (7 days) | `0` turns soft delete off. |
| `data_locations` | list of regions | unset | Configurable dual-region (`custom_placement_config`), e.g. `location: US` + `[US-EAST1, US-WEST1]`. Changing it replaces the bucket. |
| `autoclass` | `true`/`false` or `{enabled, terminal_storage_class}` | unset | `terminal_storage_class`: `NEARLINE` or `ARCHIVE`. `enabled` defaults to true when the mapping is given. Needs `storage_class: STANDARD` and no lifecycle rule using `SetStorageClass` or `matches_storage_class`. |
| `retention_policy` | `{retention_period, is_locked}` | unset | `retention_period` in seconds, 1–3155760000. **`is_locked: true` is irreversible.** |
| `logging` | `{log_bucket, log_object_prefix}` | unset | `log_bucket` is the literal name of an existing bucket. |
| `website` | `{main_page_suffix, not_found_page}` | unset | |
| `cors` | list of `{origin, method, response_header, max_age_seconds}` | none | The three lists are lists of strings. |
| `lifecycle_rules` | list of rules | none | See below. At most 100. |

### Lifecycle rules

```yaml
lifecycle_rules:
  - action:
      type: SetStorageClass        # Delete | SetStorageClass | AbortIncompleteMultipartUpload
      storage_class: NEARLINE      # required for SetStorageClass, not allowed otherwise
    condition:                     # at least one criterion
      age: 30
      matches_storage_class: [STANDARD]
```

Condition criteria:

| Criterion | Value |
|---|---|
| `age`, `num_newer_versions`, `days_since_custom_time`, `days_since_noncurrent_time` | whole number ≥ 0 (a `0` is sent to the API) |
| `size_above_bytes`, `size_below_bytes` | whole number ≥ 0 |
| `created_before`, `custom_time_before`, `noncurrent_time_before` | date `YYYY-MM-DD` (quoted or not) |
| `with_state` | `LIVE`, `ARCHIVED`, `ANY` |
| `matches_storage_class` | list of storage classes (plus `DURABLE_REDUCED_AVAILABILITY`) |
| `matches_prefix`, `matches_suffix` | list of strings |

`AbortIncompleteMultipartUpload` only accepts `age`, `matches_prefix` and
`matches_suffix`. Action types and enumerations are case-insensitive.

The provider drops zero values unless its `send_*_if_zero` flags are set. The
module sets those flags only when you write a `0`, so `age: 0` really means "all
matching objects".

### IAM

Each entry of a bucket's `iam` list binds one role to one or more principals:

```yaml
iam:
  - role: roles/storage.objectViewer     # required
    members:                             # full IAM member strings, any kind
      - group:data-readers@example.com
      - principalSet://iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/github/attribute.repository/org/repo
    users: [alice@example.com]           # shorthand: "user:" is added
    groups: [analysts@example.com]       # shorthand: "group:" is added
    service_accounts: [etl@p.iam.gserviceaccount.com]  # shorthand: "serviceAccount:" is added
    domains: [example.com]               # shorthand: "domain:" is added
    mode: authoritative                  # or additive (default: authoritative)
    condition:                           # optional IAM condition
      title: expires-2027                # required
      description: Temporary access      # optional
      expression: request.time < timestamp("2027-01-01T00:00:00Z")   # required (CEL)
```

`role` may be a predefined role (`roles/storage.objectViewer`) or a custom role
(`projects/P/roles/R`, `organizations/O/roles/R`). An entry needs at least one
principal; all lists are merged, lower-cased where IAM is case-insensitive
(emails and domains), de-duplicated and sorted.

#### Principal kinds

| Principal | In `members` | Shorthand |
|---|---|---|
| Google account | `user:alice@example.com` | `users: [alice@example.com]` |
| Google group | `group:team@example.com` | `groups: [team@example.com]` |
| Service account | `serviceAccount:sa@p.iam.gserviceaccount.com` | `service_accounts: [sa@p.iam.gserviceaccount.com]` |
| Workspace / Cloud Identity domain | `domain:example.com` | `domains: [example.com]` |
| Anyone on the internet | `allUsers` | |
| Any signed-in Google account | `allAuthenticatedUsers` | |
| Project convenience values | `projectOwner:P`, `projectEditor:P`, `projectViewer:P` | |
| Workload/workforce identity (one identity) | `principal://iam.googleapis.com/...` | |
| Workload/workforce identity (set) | `principalSet://iam.googleapis.com/...` | |

Anything else, such as a bare email, a wrong-case prefix (`serviceaccount:`,
`allusers`) or `deleted:` principals, is rejected with a message listing the
accepted formats.

#### Modes

- **`authoritative`** (default) → `google_storage_bucket_iam_binding`.
  Terraform owns the complete member list of that role (per condition) on the
  bucket: members added elsewhere, such as in the console, are removed on the
  next apply.
- **`additive`** → one `google_storage_bucket_iam_member` per member. Only
  those members are managed; others holding the role are left alone.

Each role may appear only once per bucket without a condition, plus once per
distinct condition title. Declaring the same role (and condition title) twice,
including once authoritative and once additive, is rejected, because the two
resources would keep overwriting each other.

Caveats:

- The whole-policy resource (`google_storage_bucket_iam_policy`) is
  deliberately not used. It would also wipe the default
  `projectOwner`/`projectEditor`/`projectViewer` legacy bindings.
- Declaring a legacy role (`roles/storage.legacyBucketOwner`, …) as
  authoritative replaces its default convenience members. Use `additive` to
  add to it instead.
- Switching a role between modes destroys one resource type and creates the
  other. Destroying an authoritative binding clears the role, so check the
  plan and apply twice if needed.
- IAM conditions need `uniform_bucket_level_access: true`; `allUsers` and
  `allAuthenticatedUsers` need `public_access_prevention: inherited`. Both are
  checked at plan time. An organization policy can still block public access
  or principals outside your domain (domain restricted sharing).
- Principals must exist, which only the API checks at apply time.

### Templating

The YAML file is rendered with Terraform's `templatefile()` before it is
parsed, using `config_vars`. This lets one file serve several environments:

```yaml
defaults:
  location: ${location}
  versioning: ${env == "prod"}
buckets:
  - name: app-data
    deletion_policy: ${env == "prod" ? "PREVENT" : "DELETE"}
%{ if env == "prod" }
    retention_policy: {retention_period: 604800}
%{ endif }
    iam:
      - role: roles/storage.objectUser
        service_accounts: [app@${project_id}.iam.gserviceaccount.com]
%{ for team in teams }
  - name: ${team}-scratch
%{ endfor }
```

- Put directives on their own line without `~` strip markers. `~` would also
  strip the next line's indentation. The blank lines left behind are harmless.
- A literal `${` or `%{` in the file must be written `$${` or `%%{`. This
  applies inside YAML comments too.
- Referencing a variable that isn't in `config_vars` is an error from
  `templatefile()`.

See `examples/multi-environment` for a complete example.

### YAML tips and gotchas

- **Anchors**: define shared snippets under `x-` keys and reuse them with
  aliases or merge keys (`<<: *base`), as in `examples/data-lake` and
  `examples/complete`.
- **Quote ambiguous scalars**: unquoted `yes`/`no`/`on`/`off` are booleans
  (`name: yes` becomes the bucket `true`), `007` is the number 7, and
  `2024-01-01` is a timestamp. The module converts timestamps back to dates
  where dates are expected, but quoting is clearer.
- **Duplicate keys** inside one mapping are not reported by Terraform's YAML
  decoder: the last one silently wins.
- Syntax errors are reported by `yamldecode` with a line and column.

## Validation

Everything is checked before planning, and all problems are reported together:

```
Error: Module output value precondition failed
  ...
Invalid bucket configuration in ./buckets.yaml:
  - bucket "Bad_Name": iam[0] (roles/storage.objectViewer): invalid member "alice@example.com" (expected user:EMAIL, group:EMAIL, serviceAccount:EMAIL, domain:DOMAIN, allUsers, allAuthenticatedUsers, projectOwner:PROJECT_ID, projectEditor:PROJECT_ID, projectViewer:PROJECT_ID, principal://... or principalSet://...)
  - bucket "Bad_Name": name "Bad_Name" may only contain lowercase letters, digits, dashes, underscores and dots, and must start and end with a letter or digit
  - bucket "ok-bucket": location is required (set it on the bucket or under defaults)
```

What is checked:

- **Structure:** the document is a mapping with `buckets`; no unknown keys at
  any level (typos like `storage_clas` are errors); every value has the right
  type.
- **Names:** the GCS naming rules on the final name (with `name_prefix`),
  including length, characters, dotted names, IP addresses, the `goog` prefix
  and `google` look-alikes. Names must also be unique.
- **Values:** enumerations, project ID/location/KMS key formats, labels,
  soft-delete range, retention period, lifecycle criteria, CORS fields and
  date formats.
- **Combinations:**
  - Autoclass requires STANDARD storage and no `SetStorageClass` or
    `matches_storage_class` rules.
  - Hierarchical namespace requires uniform bucket-level access and excludes
    versioning, retention policies, object retention and event-based holds.
  - IAM conditions require uniform bucket-level access.
  - Public principals require `public_access_prevention: inherited`.
- **IAM:** role format, member formats per principal kind, at least one
  principal, a valid mode, complete conditions, and no role/condition declared
  twice on a bucket.

Invalid values under `defaults` are reported once (as `defaults: ...`), not
once per bucket.

## Examples

Each `examples/*` directory is a root module (`terraform init && terraform
apply -var project_id=...`). Bucket names are global across Cloud Storage, so
change them before applying. The test suite plans every example YAML file.

| Example | Shows |
|---|---|
| `basic` | Defaults, versioning, a lifecycle rule, shorthand principal lists |
| `complete` | Every attribute and every principal kind: CMEK, retention, logging, website/CORS, autoclass, dual-region + turbo replication, HNS, object retention, requester pays, conditional and additive bindings, anchors |
| `data-lake` | A realistic multi-bucket layout with per-layer lifecycle and access, shared IAM through anchors, workload identity |
| `static-website` | Public read (`allUsers`) with `public_access_prevention: inherited`, deploys from GitHub Actions through workload identity federation |
| `multi-environment` | One templated YAML file for dev and prod (`config_vars`, conditionals, loops, `name_prefix`), with `dev.tfvars`/`prod.tfvars` |

## Testing

All suites under `tests/` run offline: no GCP credentials, no network calls
beyond downloading providers.

```sh
terraform init                     # also installs the modules the tests use
terraform test                     # every offline suite
terraform test -filter=tests/config_validation.tftest.hcl   # one file (use tests\... on Windows)
terraform fmt -check -recursive
tflint --recursive                 # uses .tflint.hcl
```

| File | What it covers |
|---|---|
| `tests/config_normalization.tftest.hcl` | `modules/config` on valid input: built-in defaults, `defaults` precedence, explicit nulls, label merging, project fallback, `name_prefix`, case normalisation, YAML dates, zero values, string→bool/number conversion, autoclass forms, optional blocks, every principal kind and member normalisation, IAM modes/conditions/keys, empty lists, anchors and merge keys, edge-case names |
| `tests/config_validation.tftest.hcl` | Every validation rule with the **exact** error messages, aggregation and sorting, and that nothing is produced while errors exist |
| `tests/module.tftest.hcl` | Root module with a mocked provider: invalid YAML fails the plan (`expect_failures`), variable validations, rendering of defaults and lifecycle rules, unset blocks omitted, resource keys unchanged by reordering, outputs after a mocked apply |
| `tests/examples.tftest.hcl` | Every example YAML file against a mocked provider, with detailed assertions on buckets and bindings |
| `tests/provider.tftest.hcl` | Every example planned with the **real** provider, so its own schema validation and plan logic also run. A dummy access token is enough because planning new resources makes no API calls. |
| `tests/fixtures/` | YAML inputs for the root-module tests |

Assertions compare structured values with `jsonencode(a) == jsonencode(b)`:
Terraform's `==` is type-strict (a `list(string)` never equals a tuple
literal), so plain comparisons can fail for the wrong reason. `run` blocks that
target `./modules/config` need a fresh `terraform init` whenever a test file
is added.

### Live test (real GCP, opt-in)

`tests/integration` is not part of the default run. It needs credentials with
permission to create and delete buckets and set their IAM policies
(`roles/storage.admin` on the project):

```sh
gcloud auth application-default login
terraform init -test-directory=tests/integration
terraform test -test-directory=tests/integration -var="project_id=MY_PROJECT"
```

It creates three buckets named `tfit-<random>-...`. Their IAM entries use
principals that always exist: the project's convenience values and its Cloud
Storage service agent. The test then:

1. reads the buckets and their IAM policies back through data sources and
   checks them against the YAML
2. applies the same configuration again and checks that no bucket or IAM
   policy changed, which would reveal a permanent diff
3. destroys everything

### Verification done so far

- The 74 offline tests pass on Terraform 1.16.4 with provider 8.4.0 and with
  7.38.0. Provider 7.37.0 rejects the module, which confirms the floor.
- The suite also passes with all outbound network blocked.
- Every example plans with identical values on Terraform 1.2.7, 1.3.0 and
  1.16.4. Each example root module validates on 1.2.7 and 1.16.4.
- Mutation check: 25 bugs deliberately injected into the module (flipped
  defaults, removed checks, swapped precedence, lost labels, dropped members,
  a disabled precondition, …) are each caught by at least one test.
- `tflint` (all Terraform rules) is clean on the module and submodule.
- `trivy` on the planned examples reports only what the examples ask for:
  intentionally public buckets, direct user grants in `complete`, and
  features left off (CMEK, access logs, versioning).
- The live test has not been run yet.

## Operational notes

- **Attributes that replace the bucket** when changed: `name`, `name_prefix`,
  `project_id`, `location`, `data_locations`, `hierarchical_namespace` and
  `enable_object_retention`. Removing a bucket from the YAML destroys it.
  Destroying a bucket that still holds objects fails unless `force_destroy` is
  true. Use `deletion_policy: PREVENT` for buckets whose data you can't lose.
- **Adopting existing buckets:** import them to the module's address, then
  describe them in the YAML:

  ```hcl
  import {
    to = module.gcs.google_storage_bucket.this["existing-bucket"]
    id = "my-project/existing-bucket"
  }
  ```

- **Public access** needs `public_access_prevention: inherited` on the bucket.
  It can still be blocked by the organization policies
  `constraints/storage.publicAccessPrevention` and
  `iam.allowedPolicyMemberDomains`.
- `rpo: ASYNC_TURBO` works only on dual-region buckets, which the API checks.
- The provider adds a `goog-terraform-provisioned` label to every bucket. It
  appears in `effective_labels`, not in `labels`.

## Working on this module

- Keep `modules/config` free of providers and resources. It must never fail
  on bad input: every access to YAML data goes through `try()`/`can()`, and
  problems are appended to the error lists as `"<ref>: <message>"` strings.
  Structure lists are validated with `can(concat(x, []))` and mappings with
  `can(keys(x))`. `tostring(null)`/`tobool(null)`/`tonumber(null)` return
  null rather than failing, so check for null separately.
- Avoid `cond ? a : b` over raw YAML values of different types. HCL unifies
  both branch types even when one branch is unused, which fails or converts
  values. Use `try()` chains instead. Also avoid `tomap()` on YAML maps: it
  fails when values have no common type, as happened with labels mixing
  numbers and booleans.
- Adding a bucket attribute touches:
  1. `setting_keys` (and `bool_settings` / `enum_settings` / `pattern_settings`
     when it fits)
  2. its checks in `target_errors`, plus cross-field checks in `bucket_errors`
  3. the normalised `buckets` map
  4. the resource in `main.tf`
  5. tests in both `config_*` files and `module.tftest.hcl`, and an example
  6. this file
- Error messages are part of the interface: tests pin them exactly. Change
  them deliberately and update `tests/config_validation.tftest.hcl`.
- Before committing: `terraform fmt -recursive`, `terraform init`,
  `terraform test`, `tflint --recursive`.
