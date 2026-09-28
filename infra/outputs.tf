output "aws_region" {
  value = var.aws_region
}

output "storefront_url" {
  value = local.base_url
}

output "admin_url" {
  value = "${local.base_url}${var.magento_admin_frontname}/"
}

output "admin_user" {
  value = var.magento_admin_user
}

output "admin_password_command" {
  description = "Run this to read the generated admin password"
  value       = "aws ssm get-parameter --with-decryption --region ${var.aws_region} --name ${aws_ssm_parameter.admin_password.name} --query Parameter.Value --output text"
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "ecr_magento_repository_url" {
  value = aws_ecr_repository.magento.repository_url
}

output "ecr_varnish_repository_url" {
  value = aws_ecr_repository.varnish.repository_url
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "ecs_web_service_name" {
  value = aws_ecs_service.web.name
}

output "ecs_cron_service_name" {
  value = aws_ecs_service.cron.name
}

output "install_task_definition_arn" {
  value = aws_ecs_task_definition.install.arn
}

output "ecs_log_group" {
  value = aws_cloudwatch_log_group.ecs.name
}

output "private_subnet_ids_csv" {
  value = join(",", aws_subnet.app[*].id)
}

output "app_security_group_id" {
  value = aws_security_group.app.id
}

output "db_identifier" {
  value = aws_db_instance.this.identifier
}

output "db_endpoint" {
  value = aws_db_instance.this.address
}

output "valkey_endpoint" {
  value = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "opensearch_endpoint" {
  value = aws_opensearch_domain.this.endpoint
}

output "efs_media_id" {
  value = aws_efs_file_system.media.id
}

output "waf_web_acl" {
  value = var.enable_waf ? aws_wafv2_web_acl.this[0].name : "(disabled)"
}

output "newrelic_enabled" {
  value = local.newrelic_enabled
}

output "newrelic_metric_stream" {
  value = local.newrelic_enabled ? aws_cloudwatch_metric_stream.newrelic[0].name : "(disabled: set newrelic_license_key)"
}
