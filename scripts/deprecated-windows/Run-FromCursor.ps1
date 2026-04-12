<#
DEPRECATED — Prefer WSL bash in Cursor. See repo root WSL_COMMANDS.txt
Run from repo root (C:\dev\ansible\ansible):
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/deprecated-windows/Run-FromCursor.ps1
#>
param(
  [ValidateSet('Configure', 'CreateUsers', 'SetupKey', 'Galaxy', 'VerifyPerHost', 'VerifyAppoperator', 'EnsurePerHost', 'EnsureAppoperator')]
  [string] $Action = 'Configure',
  [string] $PemPath = ''
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
  Write-Error 'wsl.exe not found. Install WSL, then retry.'
  exit 1
}

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not (Test-Path (Join-Path $RepoRoot 'playbooks'))) {
  Write-Error "Repo root not found. Expected playbooks next to scripts/. RepoRoot=$RepoRoot"
  exit 1
}

function ConvertTo-WslPath {
  param([Parameter(Mandatory)][string] $WindowsPath)
  $full = (Resolve-Path -LiteralPath $WindowsPath).Path
  if ($full -match '^([A-Za-z]):[\\/](.*)$') {
    $drive = $Matches[1].ToLower()
    $tail = ($Matches[2] -replace '\\', '/').TrimEnd('/')
    return "/mnt/$drive/$tail"
  }
  throw "Cannot convert to WSL path: $full"
}

$wslRepo = ConvertTo-WslPath $RepoRoot

function Invoke-WslBash {
  param([Parameter(Mandatory)][string] $BashSnippet)
  Write-Host "WSL> $BashSnippet" -ForegroundColor DarkGray
  & wsl.exe -e bash -lc "$BashSnippet"
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

switch ($Action) {
  'SetupKey' {
    if (-not $PemPath) { $PemPath = Join-Path $env:USERPROFILE 'Downloads\key pair.pem' }
    if (-not (Test-Path -LiteralPath $PemPath)) {
      Write-Error "PEM not found: $PemPath"
      exit 1
    }
    $wslPem = ConvertTo-WslPath $PemPath
    Invoke-WslBash "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cp -f '$wslPem' ~/.ssh/ec2-keypair.pem && chmod 600 ~/.ssh/ec2-keypair.pem && echo 'OK: ~/.ssh/ec2-keypair.pem'"
  }
  'Galaxy' {
    Invoke-WslBash "cd '$wslRepo' && ansible-galaxy collection install -r requirements.yml -p `$HOME/.ansible/collections"
  }
  'Configure' {
    Invoke-WslBash "cd '$wslRepo' && bash scripts/run_configure_managed_identity.sh"
  }
  'CreateUsers' {
    Invoke-WslBash "cd '$wslRepo' && bash scripts/run_create_users_wsl.sh"
  }
  'VerifyPerHost' {
    Invoke-WslBash "cd '$wslRepo' && bash scripts/verify_per_host_users.sh"
  }
  'VerifyAppoperator' {
    Invoke-WslBash "cd '$wslRepo' && bash scripts/verify_appoperator_all_hosts.sh"
  }
  'EnsurePerHost' {
    Invoke-WslBash "cd '$wslRepo' && bash scripts/ensure_per_host_users.sh"
  }
  'EnsureAppoperator' {
    Invoke-WslBash "cd '$wslRepo' && bash scripts/ensure_appoperator_all_hosts.sh"
  }
}
