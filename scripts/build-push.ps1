# Builds the Magento and Varnish images locally and pushes them to ECR.
# Writes the tag to infra/image_tag.auto.tfvars so the next `terraform apply`
# rolls the ECS services onto the new images.
#
#   .\scripts\build-push.ps1                 # build + push, tag = timestamp
#   .\scripts\build-push.ps1 -NoSampleData   # smaller image without Luma sample data
param(
    [string]$Tag = (Get-Date -Format 'yyyyMMdd-HHmmss'),
    [string]$MagentoVersion = '2.4.9',
    [string]$PhpVersion = '8.4',
    [switch]$NoSampleData,
    [switch]$SkipBuild
)
. "$PSScriptRoot\common.ps1"

$magentoRepo = Get-TfOutput ecr_magento_repository_url
$varnishRepo = Get-TfOutput ecr_varnish_repository_url
$region      = Get-TfOutput aws_region
$registry    = $magentoRepo.Split('/')[0]

Write-Host "==> docker login $registry"
$token = & aws ecr get-login-password --region $region
# The token is fed through a temp file: a PowerShell pipe appends CRLF (ECR answers 400),
# and docker's stderr warnings become terminating errors under $ErrorActionPreference=Stop.
$tokenFile = [System.IO.Path]::GetTempFileName()
try {
    [System.IO.File]::WriteAllText($tokenFile, $token)
    & cmd /c "docker login --username AWS --password-stdin $registry < `"$tokenFile`" 2>&1"
    if ($LASTEXITCODE -ne 0) { throw 'docker login to ECR failed' }
} finally {
    Remove-Item $tokenFile -Force -ErrorAction SilentlyContinue
}

$sample = 'true'
if ($NoSampleData) { $sample = 'false' }

if (-not $SkipBuild) {
    Write-Host "==> building magento image ($MagentoVersion, php $PhpVersion, sample data: $sample) tag $Tag"
    & docker build `
        -f (Join-Path $RepoRoot 'docker\magento\Dockerfile') `
        --build-arg "MAGENTO_VERSION=$MagentoVersion" `
        --build-arg "PHP_VERSION=$PhpVersion" `
        --build-arg "INSTALL_SAMPLE_DATA=$sample" `
        -t "${magentoRepo}:$Tag" -t "${magentoRepo}:latest" `
        (Join-Path $RepoRoot 'docker\magento')
    if ($LASTEXITCODE -ne 0) { throw 'magento image build failed' }

    Write-Host "==> building varnish image tag $Tag"
    & docker build `
        -f (Join-Path $RepoRoot 'docker\varnish\Dockerfile') `
        --build-arg "MAGENTO_IMAGE=${magentoRepo}:$Tag" `
        -t "${varnishRepo}:$Tag" -t "${varnishRepo}:latest" `
        (Join-Path $RepoRoot 'docker\varnish')
    if ($LASTEXITCODE -ne 0) { throw 'varnish image build failed' }
}

foreach ($image in @("${magentoRepo}:$Tag", "${magentoRepo}:latest", "${varnishRepo}:$Tag", "${varnishRepo}:latest")) {
    Write-Host "==> pushing $image"
    & docker push $image
    if ($LASTEXITCODE -ne 0) { throw "push failed: $image" }
}

$tfvars = Join-Path $InfraDir 'image_tag.auto.tfvars'
"image_tag = `"$Tag`"" | Set-Content -Encoding ascii $tfvars
Write-Host "==> wrote $tfvars"
Write-Host "Next: .\scripts\tf.ps1 apply   (first time afterwards: .\scripts\run-install.ps1)"
