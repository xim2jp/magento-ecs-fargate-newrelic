resource "aws_elasticache_subnet_group" "this" {
  name       = local.name
  subnet_ids = aws_subnet.data[*].id
}

# Valkey (Redis-compatible). Magento uses db 0 = default cache, 1 = full page cache
# (built-in FPC config; Varnish is the real FPC), 2 = sessions.
resource "aws_elasticache_replication_group" "this" {
  replication_group_id = local.name
  description          = "Magento cache + sessions"

  engine               = "valkey"
  engine_version       = var.valkey_engine_version
  parameter_group_name = "default.valkey9"
  node_type            = var.cache_node_type
  num_cache_clusters   = 1
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.cache.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = false
  automatic_failover_enabled = false
  multi_az_enabled           = false
  snapshot_retention_limit   = 0
  apply_immediately          = true

  tags = { Name = local.name }
}
