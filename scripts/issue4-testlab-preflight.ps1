$ErrorActionPreference = 'Stop'

$project = 'almanac-staging-za'
$account = gcloud config get-value account 2>$null
if ($account -ne 'tshego300@gmail.com') {
    throw "Expected tshego300@gmail.com; active account is $account"
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
