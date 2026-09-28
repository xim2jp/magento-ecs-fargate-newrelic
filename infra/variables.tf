variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "project" {
  description = "Project name (resource name prefix, ECR namespace, SSM prefix)"
  type        = string
  default     = "sunfish"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "test"
}

# ---------------------------------------------------------------- network
variable "vpc_cidr" {
  description = "VPC CIDR. Does not overlap with the other VPCs already in this account."
  type        = string
  default     = "10.60.0.0/16"
}

variable "availability_zones" {
  description = "Two AZs to use (ap-northeast-1a was 'unavailable' in this account on 2026-09-27, hence 1c/1d)"
  type        = list(string)
  default     = ["ap-northeast-1c", "ap-northeast-1d"]
}

variable "alb_allowed_cidrs" {
  description = "CIDRs allowed to reach the ALB (storefront + admin). Narrow this to your office IP if possible."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "domain_name" {
  description = "Public hostname of the shop. A certificate and a Route 53 alias are created when route53_zone_name is set."
  type        = string
  default     = "actest.examp1e.site"
}

variable "route53_zone_name" {
  description = "Route 53 public hosted zone (in this account) that contains domain_name. Empty = no DNS/certificate automation."
  type        = string
  default     = "examp1e.site"
}

variable "acm_certificate_arn" {
  description = "Optional pre-existing ACM certificate ARN (used instead of creating one for domain_name)."
  type        = string
  default     = ""
}

variable "magento_base_url" {
  description = "Optional Magento base URL override. Defaults to https://<domain_name>/ or http://<ALB DNS>/"
  type        = string
  default     = ""
}

variable "enable_waf" {
  description = "Attach an AWS WAF web ACL (managed rule groups + rate limit) to the ALB"
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "Max requests per source IP per 5 minutes before WAF blocks"
  type        = number
  default     = 3000
}

# ---------------------------------------------------------------- ecs / fargate
variable "image_tag" {
  description = "Tag of the magento / varnish images in ECR (written by scripts/build-push.ps1 into image_tag.auto.tfvars)"
  type        = string
  default     = "latest"
}

variable "web_task_cpu" {
  description = "Fargate CPU units for the web task (varnish + nginx + php-fpm)"
  type        = number
  default     = 2048
}

variable "web_task_memory" {
  description = "Fargate memory (MiB) for the web task"
  type        = number
  default     = 8192
}

variable "web_desired_count" {
  description = "Number of web tasks"
  type        = number
  default     = 1
}

variable "cron_task_cpu" {
  type    = number
  default = 1024
}

variable "cron_task_memory" {
  type    = number
  default = 4096
}

variable "cron_desired_count" {
  description = "Number of cron tasks (keep at 1; Magento cron uses DB locks but 1 is simplest)"
  type        = number
  default     = 1
}

variable "log_retention_days" {
  type    = number
  default = 14
}

# ---------------------------------------------------------------- database
variable "db_instance_class" {
  type    = string
  default = "db.t4g.medium"
}

variable "db_engine_version" {
  description = "RDS MySQL version (Magento 2.4.9 requires MySQL 8.4)"
  type        = string
  default     = "8.4.11"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

variable "db_multi_az" {
  type    = bool
  default = false
}

# ---------------------------------------------------------------- cache / search
variable "cache_node_type" {
  description = "ElastiCache Valkey node type"
  type        = string
  default     = "cache.t4g.small"
}

variable "valkey_engine_version" {
  description = "Valkey version (Magento 2.4.9 requires Valkey 9)"
  type        = string
  default     = "9.1"
}

variable "opensearch_engine_version" {
  description = "OpenSearch version (Magento 2.4.9 requires OpenSearch 3)"
  type        = string
  default     = "OpenSearch_3.3"
}

variable "opensearch_instance_type" {
  type    = string
  default = "t3.small.search"
}

variable "opensearch_volume_gb" {
  type    = number
  default = 20
}

# ---------------------------------------------------------------- magento
variable "install_sample_data" {
  description = "Must match the INSTALL_SAMPLE_DATA build arg used for the image. Only affects the install task."
  type        = bool
  default     = true
}

variable "magento_admin_frontname" {
  type    = string
  default = "admin"
}

variable "magento_admin_user" {
  type    = string
  default = "admin"
}

variable "magento_admin_email" {
  type    = string
  default = "admin@example.com"
}

variable "magento_locale" {
  type    = string
  default = "en_US"
}

variable "magento_currency" {
  type    = string
  default = "JPY"
}

variable "magento_timezone" {
  type    = string
  default = "Asia/Tokyo"
}

# ---------------------------------------------------------------- new relic
variable "newrelic_license_key" {
  description = "New Relic ingest license key. Empty = all New Relic integrations are left disabled (can be added later)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "newrelic_region" {
  description = "New Relic data center of your account: US, EU or JP"
  type        = string
  default     = "US"
  validation {
    condition     = contains(["US", "EU", "JP"], var.newrelic_region)
    error_message = "newrelic_region must be US, EU or JP."
  }
}

variable "newrelic_app_name" {
  description = "APM application name prefix (suffixes -web / -cron / -install are added)"
  type        = string
  default     = "sunfish-magento"
}

variable "newrelic_log_router_image" {
  description = "Fluent Bit image with the New Relic output plugin, used as the FireLens log router"
  type        = string
  default     = "newrelic/newrelic-fluentbit-output:3.9.0"
}

variable "newrelic_infra_image" {
  description = "New Relic ECS/Fargate infrastructure sidecar image"
  type        = string
  default     = "newrelic/nri-ecs:1.15.7"
}

variable "newrelic_metric_stream_namespaces" {
  description = "CloudWatch namespaces streamed to New Relic via Metric Streams"
  type        = list(string)
  default = [
    "AWS/ApplicationELB",
    "AWS/WAFV2",
    "AWS/ECS",
    "ECS/ContainerInsights",
    "AWS/RDS",
    "AWS/ElastiCache",
    "AWS/ES",
    "AWS/EFS",
    "AWS/NATGateway",
    "AWS/Firehose",
    "AWS/Usage",
  ]
}
