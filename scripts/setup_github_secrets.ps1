param(
    [Parameter(Mandatory = $true)]
    [string]$Repo,

    [Parameter(Mandatory = $true)]
    [string]$RemoteBaseUrl
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$androidDir = Join-Path $projectRoot 'android'
$keyPropertiesPath = Join-Path $androidDir 'key.properties'
$keystorePath = Join-Path $androidDir 'upload-keystore.jks'

if (-not (Test-Path $keyPropertiesPath)) {
    throw "未找到 $keyPropertiesPath"
}

if (-not (Test-Path $keystorePath)) {
    throw "未找到 $keystorePath"
}

$properties = @{}
Get-Content $keyPropertiesPath | ForEach-Object {
    if ($_ -match '^\s*#' -or $_ -notmatch '=') {
        return
    }
    $parts = $_ -split '=', 2
    $properties[$parts[0].Trim()] = $parts[1].Trim()
}

$storePassword = $properties['storePassword']
$keyAlias = $properties['keyAlias']
$keyPassword = $properties['keyPassword']

if ([string]::IsNullOrWhiteSpace($storePassword) -or
    [string]::IsNullOrWhiteSpace($keyAlias) -or
    [string]::IsNullOrWhiteSpace($keyPassword)) {
    throw 'key.properties 缺少必要字段'
}

$keystoreBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($keystorePath))

$keystoreBase64 | gh secret set ANDROID_KEYSTORE_BASE64 -R $Repo
$storePassword | gh secret set ANDROID_STORE_PASSWORD -R $Repo
$keyAlias | gh secret set ANDROID_KEY_ALIAS -R $Repo
$keyPassword | gh secret set ANDROID_KEY_PASSWORD -R $Repo
$RemoteBaseUrl | gh secret set REMOTE_BASE_URL -R $Repo

Write-Host "已写入 GitHub Secrets 到 $Repo"
