# Fonctions communes aux scripts du PC. A charger avec :  . "$PSScriptRoot\common.ps1"
#   $Cfg      : contenu de pc\stack.json
#   $PcRoot   : dossier pc\ du depot (config, secrets\, logs\, llama-swap\)

$PcRoot  = Split-Path $PSScriptRoot -Parent
$CfgFile = Join-Path $PcRoot 'stack.json'
if (-not (Test-Path $CfgFile)) { throw "Config absente : copie pc\stack.example.json en pc\stack.json et adapte-la." }
$Cfg = Get-Content $CfgFile -Raw | ConvertFrom-Json

$Secrets = Join-Path $PcRoot 'secrets'
$Logs    = Join-Path $PcRoot 'logs'
New-Item -ItemType Directory -Force $Secrets, $Logs | Out-Null

function Log([string]$m) { "{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $m | Add-Content (Join-Path $Logs 'stack.log') }

# Secret aleatoire, cree au premier besoin, garde dans pc\secrets\ (non versionne).
function Get-Secret([string]$name, [string]$prefix = '') {
  $f = Join-Path $Secrets $name
  if (-not (Test-Path $f)) {
    $b = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
    ($prefix + ([BitConverter]::ToString($b) -replace '-', '').ToLower()) | Set-Content $f -NoNewline -Encoding ASCII
  }
  (Get-Content $f -Raw).Trim()
}

# Adresse d'ecoute : l'IP Tailscale du PC (par defaut) ou une IP fixe (ex. 127.0.0.1).
function Get-ListenIp([int]$waitSeconds = 120) {
  if ($Cfg.listen -ne 'tailscale') { return $Cfg.listen }
  for ($i = 0; $i -lt $waitSeconds / 2; $i++) {
    $out = & tailscale ip -4 2>$null
    if ($LASTEXITCODE -eq 0 -and "$out" -match '^100\.') { return ($out | Select-Object -First 1).Trim() }
    Start-Sleep -Seconds 2
  }
  Log 'Tailscale indisponible : ecoute limitee a 127.0.0.1'
  return '127.0.0.1'
}

# Genere pc\llama-swap\llama-swap.yaml a partir du modele (chemins + cle d'API).
function Write-LlamaSwapConfig {
  $tpl = Join-Path $PcRoot 'llama-swap\llama-swap.template.yaml'
  $out = Join-Path $PcRoot 'llama-swap\llama-swap.yaml'
  $t = [IO.File]::ReadAllText($tpl)
  $t = $t.Replace('{{LLAMA_SERVER}}', ($Cfg.llama_server -replace '\\', '/'))
  $t = $t.Replace('{{MODELS_DIR}}',   ($Cfg.models_dir   -replace '\\', '/'))
  $t = $t.Replace('{{API_KEY}}',      (Get-Secret 'llama-api-key.txt' 'sk-local-'))
  [IO.File]::WriteAllText($out, $t, [Text.UTF8Encoding]::new($false))
  return $out
}

# Processus de la pile (hors agent).
function Get-StackProcesses {
  Get-CimInstance Win32_Process | Where-Object {
    $_.Name -in 'llama-swap.exe', 'llama-server.exe' -or
    ($_.Name -eq 'opencode.exe' -and $_.CommandLine -match ' serve') -or
    ($_.Name -eq 'powershell.exe' -and $_.CommandLine -match 'idle-sleep\.ps1|keep-awake\.ps1')
  }
}
