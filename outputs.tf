output "domain" {
  value = var.domain

  description = <<-END
    The site's Domain.
    END
}

output "urls" {
  value = {
    s3_bucket = "s3://${local.www_bucket}"
    url       = local.website
  }

  description = <<-END
    The URLs for the website.
    END
}

output "waf_arn" {
  value = local.waf_arn

  description = <<-END
    The WAF ARN.
    END
}
