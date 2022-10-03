data "aws_route53_zone" "this" {
  name = local.domain_base
}

locals {
  waf_input         = var.waf_arn != null
  waf_not_needed    = (var.ip_whitelist == null)
  domain_base_slice = slice(local.domain_split, 1, local.domain_split_len)
  domain_split      = split(".", var.domain)
  domain_split_len  = length(local.domain_split)
  index_html_source = "${path.module}/index.html"
  kms_key_id        = null
  log_bucket        = "${local.www_bucket}-log"
  name_prefix       = module.name.prefix
  s3_origin_id      = "s3"
  tags              = module.name.tags
  waf               = try(module.waf[0], null)
  waf_arn           = var.waf_arn == null ? try(local.waf.arn, null) : var.waf_arn
  website           = "https://${local.www_domain}"
  www_domain        = "${var.cloudfront}.${var.domain}"

  # The default favicon (may not be used depending on va )
  default_favicon = (
    "${path.module}/favicon.ico.png"
  )

  # For top level domains the domain is it's own base
  domain_base = (
    local.domain_is_top_level ? var.domain : join(".", local.domain_base_slice)
  )

  # If a domain base is only a two part domain that means it is a top level and
  # as such we should not create a subdomain.
  domain_is_top_level = (
    local.domain_split_len == 2
  )

  # See description of the "fav_icon" variable.
  favicon = (
    var.favicon == "DEFAULT" ? local.default_favicon : var.favicon
  )

  # We will not have a subdomain zone if top level domain.
  subdomain_zone = (
    try(aws_route53_zone.sub[0], null)
  )

  # Top level domain we use zone_id from base.
  # On subdomains we use the zone_id from the resource we create
  zone_id = (
    local.domain_is_top_level ? data.aws_route53_zone.this.id : aws_route53_zone.sub[0].zone_id
  )

  # In our bucket uses our s3 prefix, cloudfront, and www
  www_bucket = join("-", flatten([
    local.name_prefix, var.cloudfront, split(".", var.domain)
  ]))
}

module "acm" {
  count      = var.acm_arn == null ? 1 : 0
  depends_on = [aws_route53_record.ns]
  source     = "github.com/s3d-club/terraform-aws-acm?ref=v0.1.1"

  domain  = local.www_domain
  tags    = local.tags
  zone_id = local.zone_id
}

module "name" {
  source = "github.com/s3d-club/terraform-external-name?ref=v0.1.1"

  context = join(".", [var.cloudfront, var.domain])
  path    = path.module
  tags    = var.tags
}

module "waf" {
  count  = var.enable_waf ? 1 : 0
  source = "github.com/s3d-club/terraform-aws-waf?ref=v0.1.1"

  ip_blacklist = var.ip_blacklist
  ip_whitelist = var.ip_whitelist
  name_prefix  = join("-", ["1", local.www_bucket])
  redirects    = var.waf_redirects
  tags         = local.tags
}

resource "aws_route53_record" "www" {
  name    = var.cloudfront
  records = [aws_cloudfront_distribution.this.domain_name]
  ttl     = 300
  type    = "CNAME"
  zone_id = local.zone_id
}

resource "aws_s3_bucket_policy" "www" {
  bucket = aws_s3_bucket.www.id

  policy = jsonencode({ Version = "2012-10-17"
    Statement = [{
      Action    = "s3:GetObject"
      Effect    = "Allow"
      Principal = "*"
      Resource  = join("", ["arn:aws:s3:::", local.www_bucket, "/*"])
      Sid       = "PublicReadGetObject"
    }]
  })
}

resource "aws_s3_bucket" "logs" {
  bucket        = local.log_bucket
  force_destroy = true
  tags          = local.tags
}

resource "aws_s3_bucket" "www" {
  depends_on = [aws_s3_bucket.logs]

  tags          = local.tags
  bucket        = local.www_bucket
  force_destroy = true
}

resource "aws_s3_bucket_website_configuration" "this" {
  bucket = local.www_bucket

  index_document {
    suffix = "index.html"
  }
}

resource "aws_s3_bucket_acl" "logs" {
  acl    = "private"
  bucket = aws_s3_bucket.logs.id
}

resource "aws_cloudfront_origin_access_identity" "this" {
  comment = "Managed by the S3D Club Site TF Module"
}

resource "aws_cloudfront_distribution" "this" {
  depends_on = [time_sleep.for_s3_async_creation]

  web_acl_id          = local.waf_arn
  aliases             = [local.www_domain]
  default_root_object = "index.html"
  enabled             = true
  is_ipv6_enabled     = true
  price_class         = var.cloudfront_price_class
  tags                = local.tags

  custom_error_response {
    error_caching_min_ttl = 3000
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
  }

  custom_error_response {
    error_caching_min_ttl = 3000
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
  }

  origin {
    domain_name = aws_s3_bucket.www.bucket_regional_domain_name
    origin_id   = local.s3_origin_id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.this.cloudfront_access_identity_path
    }
  }

  logging_config {
    bucket = "${local.log_bucket}.s3.amazonaws.com"
  }

  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    default_ttl            = 60 * 60 # 1 Hour in seconds
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
    acm_certificate_arn = coalesce(var.acm_arn, module.acm[0].arn)
    ssl_support_method  = "sni-only"
  }
}

resource "time_sleep" "for_s3_async_creation" {
  depends_on = [aws_s3_bucket.www]

  create_duration = "30s"
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

resource "aws_route53_zone" "sub" {
  count = local.domain_is_top_level ? 0 : 1

  tags = local.tags
  name = var.domain
}

resource "aws_route53_record" "ns" {
  count = local.domain_is_top_level ? 0 : 1

  allow_overwrite = true
  name            = var.domain
  records         = local.subdomain_zone.name_servers
  ttl             = 60 * 3
  type            = "NS"
  zone_id         = data.aws_route53_zone.this.zone_id
}

