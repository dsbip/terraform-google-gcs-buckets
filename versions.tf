terraform {
  required_version = ">= 1.2.0"

  required_providers {
    google = {
      source = "hashicorp/google"
      # 7.38.0 is the first release with every bucket argument this module
      # sets (deletion_policy, lifecycle size_*_bytes conditions).
      version = ">= 7.38.0, < 9.0.0"
    }
  }
}
