# CloudWatch Metric Streams -> Kinesis Data Firehose -> New Relic (manual setup variant).
# Streams ALB / ECS / RDS / ElastiCache / OpenSearch / EFS / NAT metrics with ~1 min latency.
# Only created when a New Relic license key is configured.

locals {
  nr_metrics_count = local.newrelic_enabled ? 1 : 0
}

resource "aws_s3_bucket" "nr_firehose_backup" {
  count         = local.nr_metrics_count
  bucket        = "${local.name}-nr-metrics-backup-${local.account_id}"
  force_destroy = true
}

resource "aws_iam_role" "firehose" {
  count = local.nr_metrics_count
  name  = "${local.name}-nr-firehose"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "firehose.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "firehose" {
  count = local.nr_metrics_count
  name  = "s3-backup"
  role  = aws_iam_role.firehose[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:AbortMultipartUpload",
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
        "s3:PutObject"
      ]
      Resource = [
        aws_s3_bucket.nr_firehose_backup[0].arn,
        "${aws_s3_bucket.nr_firehose_backup[0].arn}/*"
      ]
    }]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "newrelic" {
  count       = local.nr_metrics_count
  name        = "${local.name}-newrelic-metrics"
  destination = "http_endpoint"

  http_endpoint_configuration {
    url                = local.nr.metrics
    name               = "New Relic"
    access_key         = var.newrelic_license_key
    buffering_size     = 1
    buffering_interval = 60
    role_arn           = aws_iam_role.firehose[0].arn
    s3_backup_mode     = "FailedDataOnly"
    retry_duration     = 60

    request_configuration {
      content_encoding = "GZIP"
    }

    s3_configuration {
      role_arn           = aws_iam_role.firehose[0].arn
      bucket_arn         = aws_s3_bucket.nr_firehose_backup[0].arn
      buffering_size     = 5
      buffering_interval = 300
      compression_format = "GZIP"
    }
  }
}

resource "aws_iam_role" "metric_stream" {
  count = local.nr_metrics_count
  name  = "${local.name}-nr-metric-stream"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "streams.metrics.cloudwatch.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "metric_stream" {
  count = local.nr_metrics_count
  name  = "firehose-put"
  role  = aws_iam_role.metric_stream[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["firehose:PutRecord", "firehose:PutRecordBatch"]
      Resource = aws_kinesis_firehose_delivery_stream.newrelic[0].arn
    }]
  })
}

resource "aws_cloudwatch_metric_stream" "newrelic" {
  count         = local.nr_metrics_count
  name          = "${local.name}-newrelic"
  role_arn      = aws_iam_role.metric_stream[0].arn
  firehose_arn  = aws_kinesis_firehose_delivery_stream.newrelic[0].arn
  output_format = "opentelemetry1.0"

  dynamic "include_filter" {
    for_each = var.newrelic_metric_stream_namespaces
    content {
      namespace = include_filter.value
    }
  }
}
