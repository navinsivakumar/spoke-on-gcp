terraform {
  required_version = ">= 0.14"
}

variable "region" {
  type        = string
  default     = "us-central1"
  description = "Region in which to run Spoke."
}

variable "project" {
  type        = string
  description = "Project in which Terraform will create resources."
}

variable "spoke_container" {
  type        = string
  description = "Name of the Spoke container to deploy. Should be a full container URL of the form 'gcr.io/$PROJECT/$NAME[:$COMMIT_SHA]'."
}

# TODO: consider making this optional.
variable "custom_domain" {
  type        = string
  description = "Domain which will be mapped to the Spoke deployment. If the domain is not registered through Google Domains or Cloud Domains, you must verify domain ownership, e.g. by running `gcloud domains verify`."
}
