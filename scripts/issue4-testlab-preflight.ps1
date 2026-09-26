[CmdletBinding()]
param(
    # The gcloud account expected to run Test Lab, e.g. -Account you@example.com.
    [Parameter(Mandatory)][string]$Account,
    [string]$Project = 'almanac-staging-za'
)

$ErrorActionPreference = 'Stop'

$active = gcloud config get-value account 2>$null
if ($active -ne $Account) {
    throw "Expected $Account; active account is $active"
}

gcloud projects describe $project `
  --format='value(projectId,projectNumber,lifecycleState)'

gcloud firebase test android models list `
  --project=$project `
  --filter='form:PHYSICAL' `
  --format='table(id,name,supportedVersionIds)'

Write-Output 'Selected candidate: model=akita (Pixel 8a), version=35'
gcloud firebase test android models describe akita `
  --project=$project `
  --format='yaml(id,name,form,perVersionInfo)'

Write-Output 'ADB devices (a physical ADB device is not required for Test Lab):'
adb devices
