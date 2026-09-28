data "aws_caller_identity" "current" {}

locals {
  name       = "${var.project}-${var.environment}"
  ssm_prefix = "/${var.project}/${var.environment}"
  account_id = data.aws_caller_identity.current.account_id

  # nonsensitive(): only the fact that a key exists is used for wiring, not the key itself
  newrelic_enabled = nonsensitive(var.newrelic_license_key != "")

  newrelic_endpoints = {
    US = {
      logs    = "https://log-api.newrelic.com/log/v1"
      metrics = "https://aws-api.newrelic.com/cloudwatch-metrics/v1"
    }
    EU = {
      logs    = "https://log-api.eu.newrelic.com/log/v1"
      metrics = "https://aws-api.eu01.nr-data.net/cloudwatch-metrics/v1"
    }
    JP = {
      logs    = "https://log-api.jp.nr-data.net/log/v1"
      metrics = "https://aws-api.jp.nr-data.net/cloudwatch-metrics/v1"
    }
  }
  nr = local.newrelic_endpoints[var.newrelic_region]

  # HTTPS is on when a certificate is provided or will be issued for domain_name
  https_enabled   = var.acm_certificate_arn != "" || (var.domain_name != "" && var.route53_zone_name != "")
  certificate_arn = var.acm_certificate_arn != "" ? var.acm_certificate_arn : (local.https_enabled ? aws_acm_certificate_validation.this[0].certificate_arn : "")

  base_url = var.magento_base_url != "" ? var.magento_base_url : (
    var.domain_name != "" ? "${local.https_enabled ? "https" : "http"}://${var.domain_name}/" : "http://${aws_lb.this.dns_name}/"
  )
}
