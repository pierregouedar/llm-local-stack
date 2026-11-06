# Shared helpers for the Windows scripts. Load with:  . "$PSScriptRoot\lib.ps1"
#   $ServerDir : the server\ folder (config.json, secrets\, logs\, generated llama-swap.yaml)
#   $Cfg       : content of server\config.json

$ServerDir = Split-Path $PSScriptRoot -Parent
$CfgFile   = Join-Path $ServerDir 'config.json'
if (-not (Test-Path $CfgFile)) { throw "Missing config: copy server\config.example.json to server\config.json and edit it." }
$Cfg = Get-Content $CfgFile -Raw | ConvertFrom-Json

$Secrets = Join-Path $ServerDir 'secrets'
$Logs    = Join-Path $ServerDir 'logs'
New-Item -ItemType Directory -Force $Secrets, $Logs | Out-Null

function Log([string]$m) { "{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $m | Add-Content (Join-Path $Logs 'stack.log') }

# Random secret, created on first use, kept in server\secrets\ (not committed).
function Get-Secret([string]$name, [string]$prefix = '') {
  $f = Join-Path $Secrets $name
  if (-not (Test-Path $f)) {
    $b = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
    ($prefix + ([BitConverter]::ToString($b) -replace '-', '').ToLower()) | Set-Content $f -NoNewline -Encoding ASCII
  }
  (Get-Content $f -Raw).Trim()
}

# Listen address: this machine's Tailscale IP (default) or a fixed IP from config.json.
function Get-ListenIp([int]$waitSeconds = 120) {
  if ($Cfg.listen -ne 'tailscale') { return $Cfg.listen }
  for ($i = 0; $i -lt $waitSeconds / 2; $i++) {
    $out = & tailscale ip -4 2>$null
    if ($LASTEXITCODE -eq 0 -and "$out" -match '^100\.') { return ($out | Select-Object -First 1).Trim() }
    Start-Sleep -Seconds 2
  }
  Log 'Tailscale unavailable: listening on 127.0.0.1 only'
  return '127.0.0.1'
}

# Builds server\llama-swap.yaml from the template (paths + API key).
function Write-LlamaSwapConfig {
  $tpl = Join-Path $ServerDir 'llama-swap.template.yaml'
  $out = Join-Path $ServerDir 'llama-swap.yaml'
  $t = [IO.File]::ReadAllText($tpl)
  $t = $t.Replace('{{LLAMA_SERVER}}', ($Cfg.llama_server -replace '\\', '/'))
  $t = $t.Replace('{{MODELS_DIR}}',   ($Cfg.models_dir   -replace '\\', '/'))
  $t = $t.Replace('{{API_KEY}}',      (Get-Secret 'llama-api-key.txt' 'sk-local-'))
  [IO.File]::WriteAllText($out, $t, [Text.UTF8Encoding]::new($false))
  return $out
}

# Stack processes (the agent is not part of the stack).
function Get-StackProcesses {
  Get-CimInstance Win32_Process | Where-Object {
    $_.Name -in 'llama-swap.exe', 'llama-server.exe' -or
    ($_.Name -eq 'opencode.exe' -and $_.CommandLine -match ' serve') -or
    ($_.Name -eq 'powershell.exe' -and $_.CommandLine -match 'idle-sleep\.ps1|keep-awake\.ps1')
  }
}
