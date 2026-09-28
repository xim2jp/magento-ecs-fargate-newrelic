# Runs terraform in ./infra with credentials from .env.
#   .\scripts\tf.ps1 init
#   .\scripts\tf.ps1 plan
#   .\scripts\tf.ps1 apply
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$TerraformArgs
)
. "$PSScriptRoot\common.ps1"

& terraform -chdir="$InfraDir" @TerraformArgs
exit $LASTEXITCODE
