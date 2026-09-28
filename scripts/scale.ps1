# Cost control: scale the ECS services and optionally stop/start the RDS instance.
#   .\scripts\scale.ps1 -Web 0 -Cron 0 -StopDb     # evening
#   .\scripts\scale.ps1 -Web 1 -Cron 1 -StartDb    # morning
# (RDS auto-starts again after 7 days; OpenSearch / Valkey / NAT keep running.)
param(
    [int]$Web = 1,
    [int]$Cron = 1,
    [switch]$StopDb,
    [switch]$StartDb
)
. "$PSScriptRoot\common.ps1"

$cluster = Get-TfOutput ecs_cluster_name
$region  = Get-TfOutput aws_region
$dbId    = Get-TfOutput db_identifier

if ($StartDb) {
    Write-Host "==> starting RDS $dbId"
    & aws rds start-db-instance --region $region --db-instance-identifier $dbId --query 'DBInstance.DBInstanceStatus' --output text
}

Write-Host "==> web desired=$Web, cron desired=$Cron"
& aws ecs update-service --region $region --cluster $cluster --service web  --desired-count $Web  --query 'service.desiredCount' --output text
& aws ecs update-service --region $region --cluster $cluster --service cron --desired-count $Cron --query 'service.desiredCount' --output text

if ($StopDb) {
    Write-Host "==> stopping RDS $dbId"
    & aws rds stop-db-instance --region $region --db-instance-identifier $dbId --query 'DBInstance.DBInstanceStatus' --output text
}
