# Shared storage for pub/media (product images, uploads) across web / cron / install tasks.
resource "aws_efs_file_system" "media" {
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "elastic"
  tags             = { Name = "${local.name}-media" }
}

resource "aws_efs_mount_target" "media" {
  count           = 2
  file_system_id  = aws_efs_file_system.media.id
  subnet_id       = aws_subnet.app[count.index].id
  security_groups = [aws_security_group.efs.id]
}

# Access point pinned to www-data (uid/gid 33 in the php image)
resource "aws_efs_access_point" "media" {
  file_system_id = aws_efs_file_system.media.id

  posix_user {
    uid = 33
    gid = 33
  }

  root_directory {
    path = "/media"
    creation_info {
      owner_uid   = 33
      owner_gid   = 33
      permissions = "0775"
    }
  }

  tags = { Name = "${local.name}-media" }
}
