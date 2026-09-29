variable "yaml" {
  description = "YAML document describing the buckets (the rendered content of the root module's config_file)."
  type        = string
  nullable    = false
}

variable "project_id" {
  description = "Project used for buckets that set project_id neither on the bucket nor under defaults."
  type        = string
  default     = null
}

variable "name_prefix" {
  description = "Prefix prepended to every bucket name. Map keys keep using the names from the YAML document."
  type        = string
  default     = ""
  nullable    = false
}

variable "labels" {
  description = "Labels applied to every bucket; labels from the YAML document win on key collisions."
  type        = map(string)
  default     = {}
  nullable    = false
}
