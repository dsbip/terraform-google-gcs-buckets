variable "config_file" {
  description = "Path to the YAML file that declares the buckets and their IAM bindings (schema in CLAUDE.md). Relative paths are resolved from the directory Terraform runs in, so prefer \"$${path.module}/buckets.yaml\"."
  type        = string
  nullable    = false

  validation {
    condition     = fileexists(var.config_file)
    error_message = "The config_file does not exist."
  }
}

variable "config_vars" {
  description = "Variables for the YAML file, which is rendered with templatefile() before it is parsed (for example $${project_id} or $${env}). A literal \"$${\" or \"%%{\" in the file must be escaped as \"$$${\" or \"%%%{\"."
  type        = any
  default     = {}
  nullable    = false

  validation {
    condition     = can(keys(var.config_vars))
    error_message = "The config_vars value must be a map or object."
  }
}

variable "project_id" {
  description = "Project for buckets that set project_id neither on the bucket nor under defaults. When null as well, the provider's project is used."
  type        = string
  default     = null
}

variable "name_prefix" {
  description = "Prefix prepended to every bucket name from the YAML file (for example \"acme-prod-\"), so one file can serve several environments. Resource keys and output keys keep using the names from the file."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9._-]*$", var.name_prefix))
    error_message = "The name_prefix may only contain lowercase letters, digits, dashes, underscores and dots."
  }
}

variable "labels" {
  description = "Labels applied to every bucket. Labels from the YAML file (defaults, then the bucket itself) win on key collisions."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition = length(var.labels) <= 64 && alltrue([
      for k, v in var.labels :
      can(regex("^[\\p{Ll}\\p{Lo}][\\p{Ll}\\p{Lo}\\p{N}_-]{0,62}$", k)) && can(regex("^[\\p{Ll}\\p{Lo}\\p{N}_-]{0,63}$", v))
    ])
    error_message = "At most 64 labels are allowed. Label keys must start with a lowercase letter and contain only lowercase letters, digits, '_' and '-' (at most 63 characters); values may contain the same characters (at most 63)."
  }
}
