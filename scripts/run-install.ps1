# Runs the one-off "install" ECS task (setup:install on first run, setup:upgrade afterwards)
# and streams its CloudWatch log until it finishes.
#   .\scripts\run-install.ps1
param(
    [int]$TimeoutMinutes = 90
)
. "$PSScriptRoot\common.ps1"

$cluster  = Get-TfOutput ecs_cluster_name
$taskDef  = Get-TfOutput install_task_definition_arn
$subnet   = (Get-TfOutput private_subnet_ids_csv).Split(',')[0]
$sg       = Get-TfOutput app_security_group_id
$logGroup = Get-TfOutput ecs_log_group
$region   = Get-TfOutput aws_region

$netcfg = "awsvpcConfiguration={subnets=[$subnet],securityGroups=[$sg],assignPublicIp=DISABLED}"
$taskArn = & aws ecs run-task --region $region --cluster $cluster --launch-type FARGATE `
    --platform-version LATEST --task-definition $taskDef --network-configuration $netcfg `
    --query 'tasks[0].taskArn' --output text
if ($LASTEXITCODE -ne 0 -or -not $taskArn -or $taskArn -eq 'None') { throw 'run-task failed' }

$taskId = $taskArn.Split('/')[-1]
$stream = "install/php/$taskId"
Write-Host "==> install task started: $taskArn"
Write-Host "    log stream: $logGroup / $stream"

$deadline  = (Get-Date).AddMinutes($TimeoutMinutes)
$nextToken = $null
$status    = ''
do {
    Start-Sleep -Seconds 15
    $status = & aws ecs describe-tasks --region $region --cluster $cluster --tasks $taskArn --query 'tasks[0].lastStatus' --output text

    $args = @('logs', 'get-log-events', '--region', $region, '--log-group-name', $logGroup, '--log-stream-name', $stream, '--start-from-head')
    if ($nextToken) { $args += @('--next-token', $nextToken) }
    $raw = & aws @args 2>$null
    if ($LASTEXITCODE -eq 0 -and $raw) {
        $resp = $raw | ConvertFrom-Json
        foreach ($e in $resp.events) { Write-Host $e.message }
        if ($resp.nextForwardToken) { $nextToken = $resp.nextForwardToken }
    } else {
        Write-Host "    [$status] waiting for logs..."
    }
} while ($status -ne 'STOPPED' -and (Get-Date) -lt $deadline)

$exitCode = & aws ecs describe-tasks --region $region --cluster $cluster --tasks $taskArn --query 'tasks[0].containers[0].exitCode' --output text
$reason   = & aws ecs describe-tasks --region $region --cluster $cluster --tasks $taskArn --query 'tasks[0].stoppedReason' --output text
Write-Host "==> task $status, exit code $exitCode ($reason)"
if ($exitCode -ne '0') { exit 1 }
