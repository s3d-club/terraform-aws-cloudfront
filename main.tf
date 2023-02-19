data "aws_route53_zone" "this" {
  name = var.domain
}

locals {
  log_bucket      = "${local.www_bucket}-log"
  name_prefix     = module.name.prefix
  s3_origin_id    = "s3"
  tags            = module.name.tags
  waf             = try(module.waf[0], null)
  waf_arn         = var.waf_arn == null ? try(local.waf.arn, null) : var.waf_arn
  website         = "https://${local.www_domain}"
  www_domain      = var.name == null ? var.domain : "${var.name}.${var.domain}"
  zone_id         = data.aws_route53_zone.this.id
  www_bucket      = coalesce(var.www_bucket, substr(local.name_prefix, 0, 60))
  default_favicon = "${path.module}/favicon.ico.png"

  # See description of the "fav_icon" variable.
  favicon = (
    var.favicon == "DEFAULT" ? local.default_favicon : var.favicon
  )
}

module "acm" {
  count  = var.acm_arn == null ? 1 : 0
  source = "github.com/s3d-club/terraform-aws-acm?ref=v1003004.2.0"

  domain                    = local.www_domain
  tags                      = local.tags
  subject_alternative_names = var.subject_alternative_names
}

module "name" {
  source = "github.com/s3d-club/terraform-external-data-name-tags?ref=v1.1.0"

  context = var.name == null ? var.domain : join(".", [var.name, var.domain])
  path    = path.module
  tags    = var.tags
}

module "waf" {
  count  = var.enable_waf ? 1 : 0
  source = "github.com/s3d-club/terraform-aws-waf?ref=v1.1.0"

  ip_blacklist = var.ip_blacklist
  ip_whitelist = var.ip_whitelist
  kms_key_arn  = var.kms_key_arn
  name_prefix  = join("-", ["1", local.www_bucket])
  redirects    = var.waf_redirects
  tags         = local.tags
}

resource "aws_cloudfront_distribution" "this" {
  depends_on = [time_sleep.for_s3_async_creation]

  web_acl_id          = local.waf_arn
  aliases             = [local.www_domain]
  default_root_object = var.default_root_object
  enabled             = true
  is_ipv6_enabled     = var.enable_ip6
  price_class         = var.cloudfront_price_class
  tags                = local.tags

  dynamic "custom_error_response" {
    for_each = var.single_page_application ? [1] : []

    content {
      error_caching_min_ttl = 1
      error_code            = 403
      response_code         = 200
      response_page_path    = "/index.html"
    }
  }

  dynamic "custom_error_response" {
    for_each = var.single_page_application ? [1] : []

    content {
      error_caching_min_ttl = 1
      error_code            = 404
      response_code         = 200
      response_page_path    = "/index.html"
    }
  }

  origin {
    domain_name              = aws_s3_bucket.www.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
    origin_id                = local.s3_origin_id
  }

  logging_config {
    bucket = "${local.log_bucket}.s3.amazonaws.com"
  }

  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    default_ttl            = 0
    max_ttl                = 60 * 60 * 24
    min_ttl                = 0
    target_origin_id       = local.s3_origin_id
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = coalesce(var.acm_arn, module.acm[0].arn)
    minimum_protocol_version = "TLSv1.2_2021"
    ssl_support_method       = "sni-only"
  }
}

resource "aws_cloudfront_origin_access_control" "this" {
  name                              = local.name_prefix
  description                       = ""
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_origin_access_identity" "this" {
  comment = "Managed TF Module"
}

resource "aws_route53_record" "www" {
  multivalue_answer_routing_policy = false
  name                             = var.name == null ? var.domain : var.name
  set_identifier                   = ""
  type                             = "A"
  zone_id                          = local.zone_id

  alias {
    evaluate_target_health = false
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = var.cloudfront_zone_id
  }
}

# We do not log or version the log content; (that would be silly!)
#   tfsec:ignore:aws-s3-enable-bucket-encryption
#   tfsec:ignore:aws-s3-enable-bucket-logging
#   tfsec:ignore:aws-s3-enable-versioning
#   tfsec:ignore:aws-s3-encryption-customer-key
resource "aws_s3_bucket" "logs" {
  bucket        = local.log_bucket
  force_destroy = true
  tags          = local.tags
}

# We do not log or version the www content
#   tfsec:ignore:aws-s3-enable-bucket-encryption
#   tfsec:ignore:aws-s3-enable-bucket-logging
#   tfsec:ignore:aws-s3-enable-versioning
#   tfsec:ignore:aws-s3-encryption-customer-key
resource "aws_s3_bucket" "www" {
  depends_on = [aws_s3_bucket.logs]

  tags          = local.tags
  bucket        = local.www_bucket
  force_destroy = true
}

resource "aws_s3_bucket_acl" "logs" {
  acl    = "private"
  bucket = aws_s3_bucket.logs.id
}

resource "aws_s3_bucket_policy" "www" {
  bucket = aws_s3_bucket.www.id

  policy = jsonencode({
    Id      = "PolicyForCloudFrontPrivateContent"
    Version = "2008-10-17"

    Statement = [
      {
        Action    = ["s3:GetObject"]
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Resource  = "arn:aws:s3:::${local.www_bucket}/*",
        Sid       = "AllowCloudFrontServicePrincipal"

        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.this.arn
          }
        }
      },
    ]
  })
}

resource "aws_s3_bucket_public_access_block" "logs" {
  block_public_acls       = true
  block_public_policy     = true
  bucket                  = aws_s3_bucket.logs.id
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# It is fine if the bucket is public because it is web content
# tfsec:ignore:aws-s3-block-public-acls
# tfsec:ignore:aws-s3-block-public-policy
# tfsec:ignore:aws-s3-ignore-public-acls
# tfsec:ignore:aws-s3-no-public-buckets
resource "aws_s3_bucket_public_access_block" "www" {
  block_public_acls       = true
  block_public_policy     = true
  bucket                  = aws_s3_bucket.www.id
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_website_configuration" "this" {
  bucket = local.www_bucket

  index_document {
    suffix = "index.html"
  }
}

resource "aws_s3_object" "favicon" {
  depends_on = [time_sleep.for_s3_async_creation]
  count      = var.favicon == null ? 0 : 1

  bucket       = local.www_bucket
  content_type = "image/png"
  etag         = filemd5(local.favicon)
  key          = "favicon.ico"
  source       = local.favicon
}

resource "time_sleep" "for_s3_async_creation" {
  depends_on = [aws_s3_bucket.www]

  create_duration = "30s"
}
