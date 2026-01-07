output "website_url" {
  value = "https://${aws_cloudfront_distribution.website-s3-distribution.domain_name}"
}

output "s3_bucket_name" {
  value = aws_s3_bucket.website_bucket.bucket
}