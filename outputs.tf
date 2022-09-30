output "domain" {
  value = var.domain

  description = <<-END
		The Site's Domain
		https://go.s3d.com/aws/site#domain
    END
}

output "urls" {
  value = {
    s3_bucket = "s3://${local.www_bucket}"
    url       = local.website
  }

  description = <<-END
    URLs for the website
		https://go.s3d.com/aws/site#urls
    END
}

output "waf_arn" {
  value = local.waf_arn

  description = <<-END
    The WAF ARN
		https://go.s3d.com/aws/site#waf_arn
    END
}
