output "errors" {
  description = "Validation errors found in the document, sorted by bucket. Empty when the document is valid."
  value       = local.errors
}

output "buckets" {
  description = "Normalised bucket settings keyed by the name used in the YAML document. Empty when there are errors."
  value       = local.buckets
}

output "iam_bindings" {
  description = "Authoritative role bindings (one per bucket, role and condition), keyed by \"bucket|role[|condition title]\". Empty when there are errors."
  value       = local.iam_bindings
}

output "iam_members" {
  description = "Additive role grants (one per member), keyed by \"bucket|role[|condition title]|member\". Empty when there are errors."
  value       = local.iam_members
}
