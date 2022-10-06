variable "acm_arn" {
  default = null
  type    = string

  description = <<-END
    AWS Certificate Manager ARN
    https://go.s3d.club/tf/site#arn
    END
}

variable "az_blacklist" {
  default = null
  type    = list(string)

  description = <<-END
    The availability zone blacklist
    https://go.s3d.club/tf/site#az_blacklist
    END
}

variable "cloudfront_price_class" {
  default = "PriceClass_100"
  type    = string

  description = <<-END
    The Cloudfront PriceClass
    https://go.s3d.club/tf/site#cloudfront_price_class
    END
}

variable "domain" {
  type = string

  description = <<-END
    The `domain` name
    https://go.s3d.club/tf/site#domain
    END
}

variable "enable_ip6" {
  default = false
  type    = bool

  description = <<-END
    an option to enable IP6 addressing.
    https://go.s3d.club/tf/site#enable_ip6
    END
}

variable "enable_waf" {
  default = false
  type    = bool

  description = <<-END
    Enable the WAF (adds costs estimate TBD!)
    https://go.s3d.club/tf/site#enable_waf
    END
}

variable "favicon" {
  default = "DEFAULT"
  type    = string

  description = <<-END
    Favicon path _(or `null` to disable)_
    https://go.s3d.club/tf/site#favicon
    END
}

variable "ip_blacklist" {
  default = null
  type    = list(string)

  description = <<-END
    The IP Blacklist
    https://go.s3d.club/site#ip_blacklist
    END
}

variable "ip_whitelist" {
  default = null
  type    = list(string)

  description = <<-END
    The IP Whitelist
    https://go.s3d.club/site#ip_whitelist
    END
}

variable "kms_key_arn" {
  type = string

  description = <<-END
    KMS key arn
    https://go.s3d.club/tf/site#kms_key_arn
    END
}

variable "name" {
  default = "www"
  type    = string

  description = <<-END
    The subdomain for Cloudfront
    https://go.s3d.club/tf/site#name
    END
}

variable "s3_prefix" {
  default = null
  type    = string

  description = <<-END
    S3 Prefix
    https://go.s3d.club/aws/site#s3_prefix
    END
}

variable "subject_alternative_names" {
  default = []
  type    = list(string)

  description = <<-END
    Subject alternative names
    https://go.s3d.club/aws/site#subject_alternative_names
    END
}

variable "tags" {
  type = map(string)

  description = <<-END
    Tags for resources
    https://go.s3d.club/aws/site#tags
    END
}

variable "waf_arn" {
  default = null
  type    = string

  description = <<-END
    The WAF ARN
    https://go.s3d.club/aws/site#waf_arn
    END
}

variable "waf_redirects" {
  default = null
  type    = map(string)

  description = <<-END
    The WAF Redirects
    https://go.s3d.club/aws/site#waf_redirects
    END
}
