# terraform-google-gcs-buckets

Terraform module that creates Google Cloud Storage buckets and their IAM role
bindings from one YAML file. Each bucket in the file gets its own settings,
lifecycle rules and role bindings for users, groups, service accounts,
domains, public access, project convenience values or workload/workforce
identity principals.

The YAML is validated at plan time: every mistake in the file is reported in
one error, and nothing is created while the file is invalid.

```hcl
module "gcs" {
  source = "git::https://github.com/dsbip/terraform-google-gcs-buckets.git?ref=main"

  config_file = "${path.module}/buckets.yaml"
  project_id  = "my-project"
}
```

```yaml
defaults:
  location: US-CENTRAL1

buckets:
  - name: acme-app-uploads
    versioning: true
    iam:
      - role: roles/storage.objectViewer
        groups: [app-readers@example.com]
      - role: roles/storage.objectCreator
        members: [serviceAccount:uploader@my-project.iam.gserviceaccount.com]
```

- **Documentation** (YAML schema, principal kinds, IAM modes, validation
  rules, testing): [CLAUDE.md](CLAUDE.md)
- **Examples:** [basic](examples/basic), [complete](examples/complete),
  [data-lake](examples/data-lake), [static-website](examples/static-website),
  [multi-environment](examples/multi-environment)
- **Tests:** `terraform init && terraform test` runs the offline suite (no
  credentials needed; Terraform ≥ 1.7). The live test in `tests/integration`
  is opt-in.

Requirements: Terraform ≥ 1.2, Google provider ≥ 7.38.0 and < 9.0.0.
