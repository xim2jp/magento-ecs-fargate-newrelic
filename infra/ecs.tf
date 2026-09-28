resource "aws_ecs_cluster" "this" {
  name = local.name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${local.name}"
  retention_in_days = var.log_retention_days
}

# ---------------------------------------------------------------- IAM
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_kms_alias" "ssm" {
  name = "alias/aws/ssm"
}

# Execution role: pull images, write logs, read SSM secrets for injection
resource "aws_iam_role" "task_execution" {
  name               = "${local.name}-ecs-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "task_execution_secrets" {
  name = "read-ssm-secrets"
  role = aws_iam_role.task_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameters", "ssm:GetParameter"]
        Resource = "arn:aws:ssm:${var.aws_region}:${local.account_id}:parameter${local.ssm_prefix}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = data.aws_kms_alias.ssm.target_key_arn
      }
    ]
  })
}

# Task role: what the running containers may do (ECS Exec, EFS)
resource "aws_iam_role" "task" {
  name               = "${local.name}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy" "task" {
  name = "task-permissions"
  role = aws_iam_role.task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EcsExec"
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      },
      {
        Sid      = "EfsMedia"
        Effect   = "Allow"
        Action   = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"]
        Resource = aws_efs_file_system.media.arn
      }
    ]
  })
}

# ---------------------------------------------------------------- shared container config
locals {
  magento_image = "${aws_ecr_repository.magento.repository_url}:${var.image_tag}"
  varnish_image = "${aws_ecr_repository.varnish.repository_url}:${var.image_tag}"

  magento_env = [
    { name = "MAGE_MODE", value = "production" },
    { name = "MAGENTO_BASE_URL", value = local.base_url },
    { name = "MAGENTO_DB_HOST", value = aws_db_instance.this.address },
    { name = "MAGENTO_DB_NAME", value = aws_db_instance.this.db_name },
    # RDS grants the master user its privileges through rds_superuser_role, which Magento's
    # privilege check cannot see. The install task creates a dedicated app user with direct
    # grants (same password) and every container connects as that user.
    { name = "MAGENTO_DB_USER", value = "magento_app" },
    { name = "MAGENTO_DB_ADMIN_USER", value = aws_db_instance.this.username },
    { name = "MAGENTO_REDIS_HOST", value = aws_elasticache_replication_group.this.primary_endpoint_address },
    { name = "MAGENTO_REDIS_PORT", value = "6379" },
    { name = "MAGENTO_OPENSEARCH_HOST", value = "https://${aws_opensearch_domain.this.endpoint}" },
    { name = "MAGENTO_OPENSEARCH_PORT", value = "443" },
    { name = "MAGENTO_ADMIN_FRONTNAME", value = var.magento_admin_frontname },
    { name = "MAGENTO_ADMIN_USER", value = var.magento_admin_user },
    { name = "MAGENTO_ADMIN_EMAIL", value = var.magento_admin_email },
    { name = "MAGENTO_LOCALE", value = var.magento_locale },
    { name = "MAGENTO_CURRENCY", value = var.magento_currency },
    { name = "MAGENTO_TIMEZONE", value = var.magento_timezone },
    { name = "MAGENTO_INSTALL_SAMPLE_DATA", value = tostring(var.install_sample_data) },
    { name = "NEW_RELIC_ENABLED", value = tostring(local.newrelic_enabled) },
    { name = "NEW_RELIC_LABELS", value = "project:${var.project};environment:${var.environment};platform:ecs-fargate" },
  ]

  magento_secrets = [
    { name = "MAGENTO_DB_PASSWORD", valueFrom = aws_ssm_parameter.db_password.arn },
    { name = "MAGENTO_CRYPT_KEY", valueFrom = aws_ssm_parameter.crypt_key.arn },
    { name = "MAGENTO_ADMIN_PASSWORD", valueFrom = aws_ssm_parameter.admin_password.arn },
    { name = "NEW_RELIC_LICENSE_KEY", valueFrom = aws_ssm_parameter.newrelic_license_key.arn },
  ]

  media_mount = {
    sourceVolume  = "media"
    containerPath = "/var/www/magento/pub/media"
    readOnly      = false
  }

  # CloudWatch Logs config per task family (always used for sidecars + install task)
  awslogs = { for p in ["web", "cron", "install", "sidecar"] : p => {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.ecs.name
      awslogs-region        = var.aws_region
      awslogs-stream-prefix = p
    }
    secretOptions = []
  } }

  # FireLens -> New Relic Logs (with ECS metadata) when a license key is configured
  firelens_log = {
    logDriver = "awsfirelens"
    options = {
      Name        = "newrelic"
      endpoint    = local.nr.logs
      Retry_Limit = "2"
    }
    secretOptions = [{ name = "licenseKey", valueFrom = aws_ssm_parameter.newrelic_license_key.arn }]
  }

  app_log = { for p in ["web", "cron"] : p => local.newrelic_enabled ? local.firelens_log : local.awslogs[p] }

  # New Relic sidecars: FireLens log router + Infrastructure agent (Fargate mode).
  # (filtered "for" instead of a conditional: Terraform rejects tuples of different length)
  sidecars = { for p in ["web", "cron"] : p => [for c in [
    {
      name              = "log_router"
      image             = var.newrelic_log_router_image
      essential         = false # keep serving traffic even if log shipping breaks
      cpu               = 0
      memoryReservation = 64
      firelensConfiguration = {
        type    = "fluentbit"
        options = { enable-ecs-log-metadata = "true" }
      }
      logConfiguration = local.awslogs["sidecar"]
    },
    {
      name              = "newrelic-infra"
      image             = var.newrelic_infra_image
      essential         = false
      cpu               = 0
      memoryReservation = 64
      environment = [
        { name = "NRIA_IS_FORWARD_ONLY", value = "true" },
        { name = "FARGATE", value = "true" },
        { name = "NRIA_OVERRIDE_HOST_ROOT", value = "" },
        { name = "NRIA_PASSTHROUGH_ENVIRONMENT", value = "ECS_CONTAINER_METADATA_URI,ECS_CONTAINER_METADATA_URI_V4,FARGATE" },
        { name = "NRIA_CUSTOM_ATTRIBUTES", value = jsonencode({ project = var.project, environment = var.environment, role = p }) },
      ]
      secrets          = [{ name = "NRIA_LICENSE_KEY", valueFrom = aws_ssm_parameter.newrelic_license_key.arn }]
      logConfiguration = local.awslogs["sidecar"]
    }
  ] : c if local.newrelic_enabled] }
}

# ---------------------------------------------------------------- task definitions
resource "aws_ecs_task_definition" "web" {
  family                   = "${local.name}-web"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.web_task_cpu
  memory                   = var.web_task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  volume {
    name = "media"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.media.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.media.id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode(concat([
    {
      name              = "php"
      image             = local.magento_image
      essential         = true
      cpu               = 0
      memoryReservation = 3072
      command           = ["php-fpm"]
      environment       = concat(local.magento_env, [{ name = "NEW_RELIC_APP_NAME", value = "${var.newrelic_app_name}-web" }])
      secrets           = local.magento_secrets
      mountPoints       = [local.media_mount]
      logConfiguration  = local.app_log["web"]
      stopTimeout       = 30
    },
    {
      name              = "nginx"
      image             = local.magento_image
      essential         = true
      cpu               = 0
      memoryReservation = 256
      command           = ["nginx", "-g", "daemon off;"]
      mountPoints       = [local.media_mount]
      dependsOn         = [{ containerName = "php", condition = "START" }]
      logConfiguration  = local.app_log["web"]
    },
    {
      name              = "varnish"
      image             = local.varnish_image
      essential         = true
      cpu               = 0
      memoryReservation = 1536
      portMappings      = [{ containerPort = 80, protocol = "tcp" }]
      environment       = [{ name = "VARNISH_SIZE", value = "1G" }]
      command           = ["-p", "http_resp_hdr_len=65536", "-p", "http_resp_size=98304", "-p", "workspace_backend=131072"]
      dependsOn         = [{ containerName = "nginx", condition = "START" }]
      logConfiguration  = local.app_log["web"]
    }
  ], local.sidecars["web"]))
}

resource "aws_ecs_task_definition" "cron" {
  family                   = "${local.name}-cron"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cron_task_cpu
  memory                   = var.cron_task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  volume {
    name = "media"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.media.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.media.id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode(concat([
    {
      name              = "php"
      image             = local.magento_image
      essential         = true
      cpu               = 0
      memoryReservation = 2048
      command           = ["cron"]
      environment       = concat(local.magento_env, [{ name = "NEW_RELIC_APP_NAME", value = "${var.newrelic_app_name}-cron" }])
      secrets           = local.magento_secrets
      mountPoints       = [local.media_mount]
      logConfiguration  = local.app_log["cron"]
      stopTimeout       = 60
    }
  ], local.sidecars["cron"]))
}

# One-off task: first install (setup:install + sample data) and later setup:upgrade runs.
resource "aws_ecs_task_definition" "install" {
  family                   = "${local.name}-install"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 2048
  memory                   = 8192
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  volume {
    name = "media"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.media.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.media.id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name             = "php"
      image            = local.magento_image
      essential        = true
      cpu              = 0
      command          = ["install"]
      # Sample data cannot be installed in production mode (MSI stock tables are created
      # lazily; Adobe KB "Errors installing optional sample data"), so the one-off install
      # container runs in developer mode. Later entries in the list override earlier ones.
      environment = concat(local.magento_env, [
        { name = "NEW_RELIC_APP_NAME", value = "${var.newrelic_app_name}-install" },
        { name = "MAGE_MODE", value = "developer" },
      ])
      secrets          = local.magento_secrets
      mountPoints      = [local.media_mount]
      logConfiguration = local.awslogs["install"]
    }
  ])
}

# ---------------------------------------------------------------- services
resource "aws_ecs_service" "web" {
  name             = "web"
  cluster          = aws_ecs_cluster.this.id
  task_definition  = aws_ecs_task_definition.web.arn
  desired_count    = var.web_desired_count
  launch_type      = "FARGATE"
  platform_version = "LATEST"

  enable_execute_command             = true
  health_check_grace_period_seconds  = 300
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = aws_subnet.app[*].id
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.web.arn
    container_name   = "varnish"
    container_port   = 80
  }

  depends_on = [
    aws_lb_listener.http,
    aws_iam_role_policy.task_execution_secrets,
    aws_iam_role_policy_attachment.task_execution_managed,
    aws_efs_mount_target.media,
  ]
}

resource "aws_ecs_service" "cron" {
  name             = "cron"
  cluster          = aws_ecs_cluster.this.id
  task_definition  = aws_ecs_task_definition.cron.arn
  desired_count    = var.cron_desired_count
  launch_type      = "FARGATE"
  platform_version = "LATEST"

  enable_execute_command             = true
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  network_configuration {
    subnets          = aws_subnet.app[*].id
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = false
  }

  depends_on = [
    aws_iam_role_policy.task_execution_secrets,
    aws_iam_role_policy_attachment.task_execution_managed,
    aws_efs_mount_target.media,
  ]
}
