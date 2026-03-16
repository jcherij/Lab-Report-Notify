terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      app              = "lab-result-notification"
      env              = "production"
      "data-sensitivity" = "phi"
      hipaa-scope      = "true"
    }
  }
}

# ---------------------------------------------------------------------------
# KMS — Customer-Managed Key for PHI encryption
# Used to encrypt lab result PDFs at rest. Rotation enabled per policy.
# ---------------------------------------------------------------------------

resource "aws_kms_key" "phi_cmk" {
  description             = "CMK for lab result notification PHI data"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Lambda"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# S3 — Lab result PDF storage
# Encrypted with PHI CMK. Public access fully blocked.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "lab_results" {
  bucket        = "${var.account_id}-lab-result-pdfs"
  force_destroy = false
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lab_results" {
  bucket = aws_s3_bucket.lab_results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.phi_cmk.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "lab_results" {
  bucket                  = aws_s3_bucket.lab_results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# SNS — Lab result notification topic
# Triggered by Lambda when a new lab result PDF is uploaded.
# Notifies the clinical team email distribution list.
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "lab_notifications" {
  name         = "lab-result-notifications"
  display_name = "Lab Result Notifications"
}

resource "aws_sns_topic_subscription" "lab_notifications_email" {
  topic_arn = aws_sns_topic.lab_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ---------------------------------------------------------------------------
# Lambda — Notification dispatcher
# Triggered by S3 PutObject events; publishes a notification to SNS
# with patient ID and result summary. Environment variables encrypted at rest.
# ---------------------------------------------------------------------------

resource "aws_lambda_function" "notify" {
  function_name = "lab-result-notify"
  role          = "arn:aws:iam::${var.account_id}:role/lab-notify-lambda-role"
  handler       = "index.handler"
  runtime       = "python3.11"
  filename      = "lambda.zip"
  kms_key_arn   = aws_kms_key.phi_cmk.arn

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.lab_notifications.arn
      RESULTS_BUCKET = aws_s3_bucket.lab_results.bucket
    }
  }

  tracing_config {
    mode = "Active"
  }
}
