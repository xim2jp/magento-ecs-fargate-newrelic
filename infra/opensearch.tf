# The account did not have the OpenSearch service-linked role yet; VPC domains need it.
resource "aws_iam_service_linked_role" "opensearch" {
  aws_service_name = "opensearchservice.amazonaws.com"
}

resource "aws_opensearch_domain" "this" {
  domain_name    = local.name
  engine_version = var.opensearch_engine_version

  cluster_config {
    instance_type          = var.opensearch_instance_type
    instance_count         = 1
    zone_awareness_enabled = false
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = var.opensearch_volume_gb
  }

  encrypt_at_rest {
    enabled = true
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  vpc_options {
    subnet_ids         = [aws_subnet.data[0].id]
    security_group_ids = [aws_security_group.opensearch.id]
  }

  # No fine-grained access control: anything that can reach the domain inside the
  # VPC (only the app security group) may use it. Magento connects without auth.
  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "*" }
      Action    = "es:*"
      Resource  = "arn:aws:es:${var.aws_region}:${local.account_id}:domain/${local.name}/*"
    }]
  })

  software_update_options {
    auto_software_update_enabled = false
  }

  tags = { Name = local.name }

  depends_on = [aws_iam_service_linked_role.opensearch]
}
