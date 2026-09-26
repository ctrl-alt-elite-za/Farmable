[CmdletBinding()]
param(
    [string]$Model = 'akita',
    [string]$Version = '35',
    [string]$Project = 'almanac-staging-za'
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$mobile = Join-Path $repo 'apps/mobile'
$evidence = Join-Path $repo 'evidence/issue-4'
New-Item -ItemType Directory -Force $evidence | Out-Null

foreach ($tool in @('flutter', 'java', 'gcloud', 'bash')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Required tool is missing: $tool"
    }
}
if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
    throw 'Android build tools are missing: adb was not found'
}

Push-Location $repo
try {
    $buildSha = (git rev-parse HEAD).Trim()
    $env:BUILD_SHA = $buildSha
    $env:TEST_MODE = 'false'
    $env:DEMO_MODE = 'false'
    $env:MOBILE_API_BASE_URL = 'https://api.invalid'

    Push-Location $mobile
    try {
        & flutter analyze integration_test/issue4_device_test.dart
        if ($LASTEXITCODE -ne 0) { throw 'Flutter analyze failed' }
        & flutter test test/device/self_test_model_test.dart test/device/self_test_cancellation_test.dart
        if ($LASTEXITCODE -ne 0) { throw 'Targeted Flutter tests failed' }
        & flutter pub get --enforce-lockfile
        if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }
        & bash ../../scripts/check-test-mode.sh
        if ($LASTEXITCODE -ne 0) { throw 'Build mode check failed' }
        & flutter build apk --debug --target-platform android-arm64 `
          --target integration_test/issue4_device_test.dart `
          --dart-define=API_URL=$env:MOBILE_API_BASE_URL `
          --dart-define=BUILD_SHA=$buildSha `
          --dart-define=TEST_MODE=$env:TEST_MODE `
          --dart-define=DEMO_MODE=$env:DEMO_MODE
        if ($LASTEXITCODE -ne 0) { throw 'Debug app APK build failed' }

        $gradlew = Join-Path (Get-Location) 'android/gradlew.bat'
        if (-not (Test-Path $gradlew)) {
            throw 'Android Gradle wrapper is not present; run the repository wrapper bootstrap before Test Lab.'
        }
        & $gradlew -p android app:assembleAndroidTest `
          '-Ptarget=../integration_test/issue4_device_test.dart'
        if ($LASTEXITCODE -ne 0) { throw 'Android instrumentation APK build failed' }
    } finally {
        Pop-Location
    }

    $appApk = Join-Path $mobile 'build/app/outputs/flutter-apk/app-debug.apk'
    $testApk = Join-Path $mobile 'build/app/outputs/apk/androidTest/app-debug-androidTest.apk'
    if (-not (Test-Path $appApk)) { throw "App APK not found: $appApk" }
    if (-not (Test-Path $testApk)) { throw "Test APK not found: $testApk" }

    $runLog = Join-Path $evidence 'android-testlab-run.txt'
    & gcloud firebase test android run `
      --project=$Project `
      --type=instrumentation `
      --app=$appApk `
      --test=$testApk `
      --device="model=$Model,version=$Version,locale=en,orientation=portrait" `
      --timeout=5m `
      --client-details="matrixLabel=issue-4-$buildSha" `
      2>&1 | Tee-Object $runLog
    if ($LASTEXITCODE -ne 0) { throw 'Firebase Test Lab run failed' }

    $reportLine = Select-String -Path $runLog -Pattern 'ISSUE4_REPORT_JSON=' | Select-Object -Last 1
    if (-not $reportLine) { throw 'Test Lab output did not contain ISSUE4_REPORT_JSON=' }
    ($reportLine.Line -replace '^.*ISSUE4_REPORT_JSON=', '') | Set-Content (Join-Path $evidence 'android-report.json')
    $report = Get-Content (Join-Path $evidence 'android-report.json') -Raw | ConvertFrom-Json
    if ($report.build_sha -ne $buildSha) {
        throw "Report build_sha $($report.build_sha) does not match APK build $buildSha"
    }
} finally {
    Pop-Location
}
