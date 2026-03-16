variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "notification_email" {
  description = "Email address to receive lab result notifications"
  type        = string
}
