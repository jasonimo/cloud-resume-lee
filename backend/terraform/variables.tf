variable "aws_region" {
  description = "Primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "S3 bucket name for the resume site (must be globally unique)"
  type        = string
}

variable "domain_name" {
  description = "Full domain name for the resume (e.g. resume.jasonlee.com)"
  type        = string
}

variable "hosted_zone_name" {
  description = "Route 53 hosted zone name (e.g. jasonlee.com)"
  type        = string
}
