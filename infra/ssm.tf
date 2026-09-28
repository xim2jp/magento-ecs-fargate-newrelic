# Secrets live in SSM Parameter Store (SecureString) and are injected into the
# containers by ECS as environment variables (task execution role reads them).

resource "random_password" "admin" {
  length      = 16
  special     = false
  min_numeric = 2
  min_upper   = 2
  min_lower   = 2
}

# Magento crypt key: must be identical in every container (it encrypts data in the DB).
resource "random_id" "crypt_key" {
  byte_length = 16
}

resource "aws_ssm_parameter" "db_password" {
  name  = "${local.ssm_prefix}/db_password"
  type  = "SecureString"
  value = random_password.db.result
}

resource "aws_ssm_parameter" "admin_password" {
  name  = "${local.ssm_prefix}/magento_admin_password"
  type  = "SecureString"
  value = random_password.admin.result
}

resource "aws_ssm_parameter" "crypt_key" {
  name  = "${local.ssm_prefix}/magento_crypt_key"
  type  = "SecureString"
  value = random_id.crypt_key.hex
}

# SSM refuses empty values, so "disabled" is stored when no key is configured;
# the entrypoint treats that value as "New Relic off".
resource "aws_ssm_parameter" "newrelic_license_key" {
  name  = "${local.ssm_prefix}/newrelic_license_key"
  type  = "SecureString"
  value = local.newrelic_enabled ? var.newrelic_license_key : "disabled"
}
