# Custom domain: ACM certificate (DNS validated) + Route 53 alias to the ALB.
# Only created when var.domain_name is set and the zone is hosted in this account.

locals {
  dns_enabled = var.domain_name != "" && var.route53_zone_name != ""
  dns_count   = local.dns_enabled ? 1 : 0
}

data "aws_route53_zone" "this" {
  count        = local.dns_count
  name         = var.route53_zone_name
  private_zone = false
}

resource "aws_acm_certificate" "this" {
  count             = local.dns_count
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = var.domain_name }
}

resource "aws_route53_record" "acm_validation" {
  for_each = local.dns_enabled ? {
    for dvo in aws_acm_certificate.this[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  zone_id         = data.aws_route53_zone.this[0].zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  count                   = local.dns_count
  certificate_arn         = aws_acm_certificate.this[0].arn
  validation_record_fqdns = [for r in aws_route53_record.acm_validation : r.fqdn]
}

resource "aws_route53_record" "site" {
  count   = local.dns_count
  zone_id = data.aws_route53_zone.this[0].zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}
