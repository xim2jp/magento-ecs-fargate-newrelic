# Shared helpers: loads AWS credentials from .env and locates the infra directory.
$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:InfraDir = Join-Path $RepoRoot 'infra'

$envFile = Join-Path $RepoRoot '.env'
if (Test-Path $envFile) {
    foreach ($line in Get-Content $envFile) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
            $value = $matches[2].Trim().Trim('"').Trim("'")
            Set-Item -Path "env:$($matches[1])" -Value $value
        }
    }
}
if (-not $env:AWS_DEFAULT_REGION) { $env:AWS_DEFAULT_REGION = 'ap-northeast-1' }

function Get-TfOutput([string]$Name) {
    $value = & terraform -chdir="$InfraDir" output -raw $Name
    if ($LASTEXITCODE -ne 0) { throw "terraform output $Name failed (run terraform apply first?)" }
    return $value
}
