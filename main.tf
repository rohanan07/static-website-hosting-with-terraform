#the main bucket where static website will be hosted
resource "aws_s3_bucket" "website_bucket" {
 bucket =  var.bucket_name
}

#block public access
resource "aws_s3_bucket_public_access_block" "block-public-access" {
  bucket = aws_s3_bucket.website_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#Origin access control for cloudfront
resource "aws_cloudfront_origin_access_control" "only-cloudfront-access" {
  name = "oac-${var.bucket_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior = "always"
  signing_protocol = "sigv4"
  description = "Origin access control for static website (only cloudfront could access the bucket)"
}

resource "aws_s3_bucket_policy" "website-bucket-policy" {
  bucket = aws_s3_bucket.website_bucket.id

  depends_on = [ aws_s3_bucket_public_access_block.block-public-access ]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.website_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.website-s3-distribution.arn
          }
        }
      }
    ]
  })
}

resource "aws_s3_object" "website-files" {
  for_each = fileset("${path.module}/www", "**/*")
  bucket = aws_s3_bucket.website_bucket.id
  key = each.value
  source = "${path.module}/www/${each.value}"
  etag   = filemd5("${path.module}/www/${each.value}")
  content_type = lookup({
    "html" = "text/html",
    "css"  = "text/css",
    "js"   = "application/javascript",
    "json" = "application/json",
    "png"  = "image/png",
    "jpg"  = "image/jpeg",
    "jpeg" = "image/jpeg",
    "gif"  = "image/gif",
    "svg"  = "image/svg+xml",
    "ico"  = "image/x-icon",
    "txt"  = "text/plain"
  }, split(".", each.value)[length(split(".", each.value)) - 1], "application/octet-stream")
}

resource "aws_cloudfront_distribution" "website-s3-distribution" {
  depends_on = [ aws_acm_certificate_validation.cert_validation ]
  origin {
    domain_name              = aws_s3_bucket.website_bucket.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.only-cloudfront-access.id
    origin_id                = "S3-${aws_s3_bucket.website_bucket.id}"
  }
  enabled = true
  is_ipv6_enabled = true
  default_root_object = "index.html"

  aliases = [ local.domain, "www.${local.domain}" ]

  default_cache_behavior {
    allowed_methods  = [ "GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.website_bucket.id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate_validation.cert_validation.certificate_arn
    ssl_support_method  = "sni-only"
  }
}

locals {
  domain = "rohanstaticwebsite.com"
}

resource "aws_acm_certificate" "cert" {
  provider = aws.us-east-1
  domain_name = "*.${local.domain}"
  subject_alternative_names = [
    "www.${local.domain}"
  ]
  validation_method = "DNS"
}

resource "aws_route53_zone" "domain" {
  name = local.domain
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  zone_id = aws_route53_zone.domain.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "cert_validation" {
  provider = aws.us-east-1
  certificate_arn = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

resource "aws_route53_record" "apex" {
  zone_id = aws_route53_zone.domain.zone_id
  name = local.domain
  type = "A"
  alias {
    name = aws_cloudfront_distribution.website-s3-distribution.domain_name
    zone_id = aws_cloudfront_distribution.website-s3-distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.domain.zone_id
  name    = "www.${local.domain}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website-s3-distribution.domain_name
    zone_id                = aws_cloudfront_distribution.website-s3-distribution.hosted_zone_id
    evaluate_target_health = false
  }
}