output "lab_results_bucket" {
  description = "S3 bucket name for lab result PDFs"
  value       = aws_s3_bucket.lab_results.bucket
}

output "sns_topic_arn" {
  description = "SNS topic ARN for lab result notifications"
  value       = aws_sns_topic.lab_notifications.arn
}

output "lambda_function_name" {
  description = "Lambda function name for the notification dispatcher"
  value       = aws_lambda_function.notify.function_name
}

output "kms_key_arn" {
  description = "PHI CMK ARN"
  value       = aws_kms_key.phi_cmk.arn
}
