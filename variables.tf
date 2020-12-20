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
