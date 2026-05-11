#!/usr/bin/env pwsh
# xray-test-suite — automatic configuration setup (PowerShell)
#
# Bootstraps config.json + ~/.claude/.xray-credentials.json from the bundled
# .sample.json files, then writes any provided values into them.
#
# USAGE
#   pwsh scripts/xray-setup.ps1                                    # interactive (terminal only)
#   pwsh scripts/xray-setup.ps1 -CloudId X -ProjectKey Y ...       # non-interactive (CI / Claude)
#   pwsh scripts/xray-setup.ps1 -Force                             # overwrite existing files
#
# EXIT CODES
#   0  Fully configured (no placeholders remain).
#   1  Hard error (sample files missing — plugin not installed correctly).
#   2  Files staged but placeholders remain (user input still needed).

[CmdletBinding()]
param(
    [string]$CloudId,
    [string]$Username,
    [string]$ProjectKey,
    [string]$ProjectName,
    [string]$XrayImportUrl,
    [string]$ApiToken,
    [string]$XrayClientId,
    [string]$XrayClientSecret,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$PluginRoot  = (Resolve-Path (Join-Path $ScriptDir '..')).Path
$Refs        = Join-Path $PluginRoot 'skills/xray-test-suite/references'
$Config      = Join-Path $Refs 'config.json'
$ConfigSample = Join-Path $Refs 'config.sample.json'
$Creds       = Join-Path $HOME '.claude/.xray-credentials.json'
$CredsSample = Join-Path $Refs 'credentials.sample.json'

if (-not (Test-Path $ConfigSample)) {
    Write-Error "Missing: $ConfigSample — is the plugin installed correctly?"
    exit 1
}
if (-not (Test-Path $CredsSample)) {
    Write-Error "Missing: $CredsSample — is the plugin installed correctly?"
    exit 1
}

if (-not (Test-Path $Config) -or $Force) {
    Copy-Item $ConfigSample $Config -Force
    Write-Host "Created: $Config"
}
$credsDir = Split-Path -Parent $Creds
if (-not (Test-Path $credsDir)) {
    New-Item -ItemType Directory -Path $credsDir -Force | Out-Null
}
if (-not (Test-Path $Creds) -or $Force) {
    Copy-Item $CredsSample $Creds -Force
    Write-Host "Created: $Creds"
}

$IsInteractive = -not [Console]::IsInputRedirected
function Prompt-Plain {
    param([string]$Current, [string]$Message, [string]$Default = '')
    if ($Current) { return $Current }
    if (-not $IsInteractive) { return '' }
    $prompt = if ($Default) { "$Message [$Default]" } else { $Message }
    $answer = Read-Host $prompt
    if (-not $answer -and $Default) { return $Default }
    return $answer
}
function Prompt-Secret {
    param([string]$Current, [string]$Message)
    if ($Current) { return $Current }
    if (-not $IsInteractive) { return '' }
    $sec = Read-Host $Message -AsSecureString
    return [System.Net.NetworkCredential]::new('', $sec).Password
}

$CloudId       = Prompt-Plain  $CloudId       'Atlassian cloudId (hostname or UUID)'
$Username      = Prompt-Plain  $Username      'Atlassian username (work email)'
$ProjectKey    = Prompt-Plain  $ProjectKey    'Jira project key (e.g. FIFAGEN)'
$ProjectName   = Prompt-Plain  $ProjectName   'Jira project display name' $ProjectKey
$XrayImportUrl = Prompt-Plain  $XrayImportUrl 'Xray Test Case Importer URL'
$ApiToken      = Prompt-Secret $ApiToken      'Atlassian API token'
$XrayClientId  = Prompt-Plain  $XrayClientId  'Xray Cloud Client ID (optional, press enter to skip)'
if ($XrayClientId) {
    $XrayClientSecret = Prompt-Secret $XrayClientSecret 'Xray Cloud Client Secret'
}

function Set-JsonField {
    param([Parameter(Mandatory)] $Object, [string]$Path, $Value)
    if (-not $Value) { return }
    $parts = $Path -split '\.'
    $cur = $Object
    for ($i = 0; $i -lt $parts.Length - 1; $i++) {
        $name = $parts[$i]
        if (-not $cur.PSObject.Properties[$name] -or $null -eq $cur.$name) {
            $cur | Add-Member -MemberType NoteProperty -Name $name -Value (New-Object PSObject) -Force
        }
        $cur = $cur.$name
    }
    $leaf = $parts[-1]
    if ($cur.PSObject.Properties[$leaf]) { $cur.$leaf = $Value }
    else { $cur | Add-Member -MemberType NoteProperty -Name $leaf -Value $Value -Force }
}

if ($CloudId -or $Username -or $ProjectKey -or $ProjectName -or $XrayImportUrl) {
    $cfg = Get-Content $Config -Raw | ConvertFrom-Json
    Set-JsonField $cfg 'atlassian.cloudId'  $CloudId
    Set-JsonField $cfg 'atlassian.username' $Username
    Set-JsonField $cfg 'project.key'        $ProjectKey
    Set-JsonField $cfg 'project.name'       $ProjectName
    Set-JsonField $cfg 'xrayImport.url'     $XrayImportUrl
    ($cfg | ConvertTo-Json -Depth 10) | Set-Content $Config -Encoding UTF8
    Write-Host "Updated: $Config"
}

if ($ApiToken -or $XrayClientId -or $XrayClientSecret) {
    $cr = Get-Content $Creds -Raw | ConvertFrom-Json
    Set-JsonField $cr 'atlassian.apiToken'     $ApiToken
    Set-JsonField $cr 'xrayCloud.clientId'     $XrayClientId
    Set-JsonField $cr 'xrayCloud.clientSecret' $XrayClientSecret
    ($cr | ConvertTo-Json -Depth 10) | Set-Content $Creds -Encoding UTF8
    Write-Host "Updated: $Creds"
}

Write-Host ''
Write-Host '=== Validation ==='
$configRaw = Get-Content $Config -Raw
$credsRaw  = Get-Content $Creds -Raw
$hasPlaceholders = $false
if ($configRaw -match '"<') {
    Write-Warning "$Config still has placeholder <...> values."
    $hasPlaceholders = $true
}
if ($credsRaw -match '"<') {
    Write-Warning "$Creds still has placeholder <...> values."
    $hasPlaceholders = $true
}
if ($hasPlaceholders) {
    Write-Host ''
    Write-Host 'Re-run with the missing values:'
    Write-Host "  pwsh $($MyInvocation.MyCommand.Path) -CloudId <id> -Username <email> -ProjectKey <KEY> ``"
    Write-Host '    -XrayImportUrl <url> -ApiToken <token> [-XrayClientId <id> -XrayClientSecret <secret>]'
    exit 2
}
Write-Host 'OK — config and credentials populated, no placeholders remain.'
