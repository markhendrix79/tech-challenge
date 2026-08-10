terraform {
  required_version = "1.15.8"

  cloud {
    
    organization = "mark-hendrix-projects"

    workspaces {
      tags = ["tech"]
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}


resource "aws_s3_bucket" "mark-hendrix-fullstack-tech-challenge" {
  bucket = "mark-hendrix-fullstack-tech-challenge-${var.environment}"
}


data "aws_iam_policy_document" "origin_bucket_policy" {
  statement {
    sid    = "AllowCloudFrontServicePrincipalReadWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]

    resources = [
      "${aws_s3_bucket.mark-hendrix-fullstack-tech-challenge.arn}/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.s3_distribution.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "mark-hendrix-fullstack-tech-challenge" {
  bucket = aws_s3_bucket.mark-hendrix-fullstack-tech-challenge.bucket
  policy = data.aws_iam_policy_document.origin_bucket_policy.json
}

locals {
  s3_origin_id = "tech-challenge-bucket"
}


resource "aws_cloudfront_origin_access_control" "default" {
  name                              = "oac-tech-challenge-${var.environment}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name              = aws_s3_bucket.mark-hendrix-fullstack-tech-challenge.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.default.id
    origin_id                = local.s3_origin_id
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"


  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA", "GB", "DE"]
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}



resource "aws_cloudwatch_log_delivery_source" "cloudfront_logs" {
  region = "us-east-1"

  name         = "Cloudfront Logs"
  log_type     = "ACCESS_LOGS"
  resource_arn = aws_cloudfront_distribution.s3_distribution.arn
}

resource "aws_s3_bucket" "cloudfront_logs" {
  bucket        = "mark-hendrix-fullstack-tech-challenge-${var.environment}-logs"
  force_destroy = true
}

resource "aws_cloudwatch_log_delivery_destination" "cloudfront_logs_s3" {
  region = "us-east-1"

  name          = "s3-destination"
  output_format = "parquet"

  delivery_destination_configuration {
    destination_resource_arn = "${aws_s3_bucket.cloudfront_logs.arn}/logs"
  }
}

resource "aws_cloudwatch_log_delivery" "example" {
  region = "us-east-1"

  delivery_source_name     = aws_cloudwatch_log_delivery_source.cloudfront_logs.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.cloudfront_logs_s3.arn

  s3_delivery_configuration {
    suffix_path = "/{DistributionId}/{yyyy}/{MM}/{dd}/{HH}"
  }
}

output "dist_id" {
    value = aws_cloudfront_distribution.s3_distribution.id
}

output "URL" {
    value = aws_cloudfront_distribution.s3_distribution.domain_name
}
