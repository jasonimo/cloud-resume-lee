terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  required_version = ">= 1.3.0"
}

provider "aws" {
  region = var.aws_region
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}


# S3 Bucket
resource "aws_s3_bucket" "resume" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_versioning" "resume" {
  bucket = aws_s3_bucket.resume.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "resume" {
  bucket = aws_s3_bucket.resume.id
  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}


# CloudFront Origin Access Control
resource "aws_cloudfront_origin_access_control" "resume" {
  name = "resume-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior = "always"
  signing_protocol = "sigv4"
}


# S3 Bucket Policy — only allow CloudFront to read
resource "aws_s3_bucket_policy" "resume" {
  bucket = aws_s3_bucket.resume.id
  policy = data.aws_iam_policy_document.resume_bucket_policy.json
}

data "aws_iam_policy_document" "resume_bucket_policy" {
  statement {
    actions = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.resume.arn}/*"]

    principals {
      type = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test = "StringEquals"
      variable = "AWS:SourceArn"
      values = [aws_cloudfront_distribution.resume.arn]
    }
  }
}



# ACM Certificate (must be us-east-1 for CloudFront)
resource "aws_acm_certificate" "resume" {
  provider = aws.us_east_1
  domain_name  = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.resume.domain_validation_options : dvo.domain_name => {
      name = dvo.resource_record_name
      record = dvo.resource_record_value
      type = dvo.resource_record_type
    }
  }

  zone_id = data.aws_route53_zone.resume.zone_id
  name = each.value.name
  type = each.value.type
  records = [each.value.record]
  ttl = 60
}

resource "aws_acm_certificate_validation" "resume" {
  provider = aws.us_east_1
  certificate_arn = aws_acm_certificate.resume.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}


# CloudFront Distribution
resource "aws_cloudfront_distribution" "resume" {
  enabled = true
  default_root_object = "index.html"
  aliases = [var.domain_name]

  origin {
    domain_name = aws_s3_bucket.resume.bucket_regional_domain_name
    origin_id = "S3-${var.bucket_name}"
    origin_access_control_id = aws_cloudfront_origin_access_control.resume.id
  }

  default_cache_behavior {
    allowed_methods = ["GET", "HEAD"]
    cached_methods = ["GET", "HEAD"]
    target_origin_id = "S3-${var.bucket_name}"
    viewer_protocol_policy = "redirect-to-https"
    compress = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl = 0
    default_ttl = 3600
    max_ttl = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate_validation.resume.certificate_arn
    ssl_support_method = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}


# Route 53
data "aws_route53_zone" "resume" {
  name = var.hosted_zone_name
  private_zone = false
}

resource "aws_route53_record" "resume" {
  zone_id = data.aws_route53_zone.resume.zone_id
  name = var.domain_name
  type = "A"

  alias {
    name = aws_cloudfront_distribution.resume.domain_name
    zone_id = aws_cloudfront_distribution.resume.hosted_zone_id
    evaluate_target_health = false
  }
}