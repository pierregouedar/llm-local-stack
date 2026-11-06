<#
Banc de mesure reproductible pour llama.cpp (Windows).

Deux mesures, chacune ajoutee a bench\results.csv :
  1. llama-bench : prefill (pp, 2048 tokens) et generation (tg, 128 tokens) a plusieurs
     profondeurs de contexte (-d). -r 3 repetitions, on garde la MEDIANE des echantillons.
  2. llama-server en conditions reelles : vrai code (dossier -CodeDir) de ~8k puis ~32k tokens
     envoye sur /completion, a froid (prefill complet), puis une 2e requete qui reprend le
     meme debut + une question : verifie que le cache evite de tout relire.
     Chaque scenario est joue 2 fois (serveur relance), on garde la mediane.

Exemple :
  .\bench.ps1 -Label "reference-bat" `
    -ServerArgs "-ngl 99 --n-cpu-moe 28 --jinja -c 262144 -fa on -ctk q8_0 -ctv q8_0 -t 8 -b 2048 -ub 2048 -np 1 --cache-reuse 256" `
    -BenchArgs  "-ngl 99 -ncmoe 28 -fa on -ctk q8_0 -ctv q8_0 -t 8 -b 2048 -ub 2048"
#>
param(
  [Parameter(Mandatory)][string]$Label,
  [string]$Model     = '',   # defaut : <models_dir>\Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_S.gguf (pc\stack.json)
  [string]$BinDir    = '',   # defaut : dossier de llama_server (pc\stack.json)
  [string]$ServerArgs = '',
  [string]$BenchArgs  = '',
  [int[]]$Depths     = @(0, 16384, 32768, 65536),
  [int[]]$PromptSizes = @(8192, 32768),
  [int]$Runs         = 2,
  [switch]$SkipBench,
  [switch]$SkipServer,
  [Parameter(Mandatory)][string]$CodeDir   # un depot de code reel : ses fichiers servent de prompts (8k, 32k, 64k...)
)

# 'Continue' : sous PowerShell 5.1, 'Stop' transforme en erreur fatale le simple texte que
# llama.cpp ecrit sur stderr. Les vraies erreurs sont levees explicitement (throw).
$ErrorActionPreference = 'Continue'

# Valeurs par defaut lues dans pc\stack.json si non fournies
$cfgFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'pc\stack.json'
if ((-not $Model -or -not $BinDir) -and (Test-Path $cfgFile)) {
  $cfg = Get-Content $cfgFile -Raw | ConvertFrom-Json
  if (-not $BinDir) { $BinDir = Split-Path $cfg.llama_server }
  if (-not $Model)  { $Model  = Join-Path $cfg.models_dir 'Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_S.gguf' }
}
if (-not $Model -or -not $BinDir) { throw 'Indique -Model et -BinDir (ou cree pc\stack.json).' }
$out     = $PSScriptRoot
$csv     = Join-Path $out 'results.csv'
$logDir  = Join-Path $out 'logs'
New-Item -ItemType Directory -Force $logDir | Out-Null
$port    = 8090
$apiKey  = 'bench-local-only'
$stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'

function Median([double[]]$v) {
  $v = $v | Sort-Object
  if (-not $v) { return $null }
  $n = $v.Count
  if ($n % 2) { return $v[[int][math]::Floor($n / 2)] }
  return ($v[$n / 2 - 1] + $v[$n / 2]) / 2
}

# --- commit llama.cpp ---------------------------------------------------------------
$ver = (& "$BinDir\llama-server.exe" --version 2>&1 | Out-String)
$commit = if ($ver -match 'build (\d+), commit ([0-9a-f]+)') { "b$($Matches[1])-$($Matches[2])" } else { 'inconnu' }

# --- suivi du pic de VRAM pendant un test -------------------------------------------
function Start-VramWatch {
  $file = Join-Path $env:TEMP "vram-$PID.txt"
  Set-Content $file 0
  $job = Start-Job -ArgumentList $file -ScriptBlock {
    param($f) $max = 0
    while ($true) {
      $v = [int](nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)
      if ($v -gt $max) { $max = $v; Set-Content $f $max }
      Start-Sleep -Milliseconds 400
    }
  }
  return @{ Job = $job; File = $file }
}
function Stop-VramWatch($w) {
  Stop-Job $w.Job -ErrorAction SilentlyContinue; Remove-Job $w.Job -Force -ErrorAction SilentlyContinue
  return [int](Get-Content $w.File)
}

function Add-Result($mode, $size, $pp, $tg, $vram, $mtp, $notes, $params) {
  [pscustomobject]@{
    date        = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    label       = $Label
    llama_cpp   = $commit
    model       = (Split-Path $Model -Leaf)
    mode        = $mode
    context     = $size
    pp_tps      = if ($pp -ne $null) { [math]::Round($pp, 1) } else { '' }
    tg_tps      = if ($tg -ne $null) { [math]::Round($tg, 1) } else { '' }
    vram_max_mib = $vram
    mtp_accept_pct = $mtp
    params      = $params
    notes       = $notes
  } | Export-Csv $csv -Append -NoTypeInformation -Encoding UTF8
}

# =====================================================================================
# 1. llama-bench
# =====================================================================================
if (-not $SkipBench) {
  $bargs = @('-m', $Model) + ($BenchArgs -split '\s+' | Where-Object { $_ }) +
           @('-p', '2048', '-n', '128', '-d', ($Depths -join ','), '-r', '3', '-o', 'json')
  Write-Host "[llama-bench] $($bargs -join ' ')"
  $w = Start-VramWatch
  $raw = & "$BinDir\llama-bench.exe" @bargs 2>"$logDir\$stamp-$Label-bench.err.txt"
  $vram = Stop-VramWatch $w
  $raw | Set-Content "$logDir\$stamp-$Label-bench.json"
  $res = ($raw | Out-String) | ConvertFrom-Json
  foreach ($r in $res) {
    $med = Median ([double[]]$r.samples_ts)
    if ($r.n_gen -gt 0) { Add-Result 'llama-bench tg128' $r.n_depth $null $med $vram '' '' $BenchArgs }
    else               { Add-Result 'llama-bench pp2048' $r.n_depth $med $null $vram '' '' $BenchArgs }
    Write-Host ("  depth {0,6} | {1} | mediane {2:N1} t/s" -f $r.n_depth, $(if ($r.n_gen -gt 0) { 'tg' } else { 'pp' }), $med)
  }
}

# =====================================================================================
# 2. llama-server en conditions reelles
# =====================================================================================
if (-not $SkipServer) {
  $files = Get-ChildItem $CodeDir -Recurse -Include *.rs, *.py, *.ts, *.js, *.go, *.toml, *.slint -File |
           Where-Object { $_.FullName -notmatch '\\target\\' } | Sort-Object FullName
  $corpus = ($files | ForEach-Object { "// ===== $($_.FullName.Substring($CodeDir.Length + 1)) =====`n" + (Get-Content $_.FullName -Raw -Encoding UTF8) }) -join "`n"
  $headers = @{ Authorization = "Bearer $apiKey" }
  $base = "http://127.0.0.1:$port"

  function Start-Server {
    # jusqu'a 3 tentatives : juste apres l'arret du serveur precedent, le GPU n'est parfois pas
    # encore libere ("CUDA error: shared object initialization failed")
    for ($try = 1; $try -le 3; $try++) {
      try { return (Start-ServerOnce) } catch {
        if ($try -eq 3) { throw }
        Write-Host "  demarrage rate ($($_.Exception.Message)), nouvel essai dans 15 s"
        Start-Sleep -Seconds 15
      }
    }
  }

  function Start-ServerOnce {
    $sargs = @('-m', "`"$Model`"") + ($ServerArgs -split '\s+' | Where-Object { $_ }) +
             @('--host', '127.0.0.1', '--port', $port, '--api-key', $apiKey, '--no-webui')
    $log = "$logDir\$stamp-$Label-server.log"
    $p = Start-Process "$BinDir\llama-server.exe" -ArgumentList $sargs -PassThru -WindowStyle Hidden `
         -RedirectStandardError $log -RedirectStandardOutput "$log.out"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    for ($i = 0; $i -lt 300; $i++) {
      Start-Sleep -Seconds 1
      if ($p.HasExited) { throw "llama-server s'est arrete au demarrage (voir $log)" }
      try { if ((Invoke-RestMethod "$base/health" -TimeoutSec 2).status -eq 'ok') { $script:loadSec += @($sw.Elapsed.TotalSeconds); return $p } } catch {}
    }
    throw "llama-server ne repond pas apres 300 s"
  }

  function Get-Prompt([int]$target, [string]$nonce) {
    # un en-tete unique par prompt : deux prompts differents ne partagent pas de debut commun
    $head = "// session $nonce : code review request`n"
    $len = [math]::Min($corpus.Length, $target * 4)
    for ($k = 0; $k -lt 8; $k++) {
      $text = $head + $corpus.Substring(0, $len)
      $n = (Invoke-RestMethod "$base/tokenize" -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' `
            -Body ([Text.Encoding]::UTF8.GetBytes((@{ content = $text } | ConvertTo-Json)))).tokens.Count
      if ([math]::Abs($n - $target) / $target -lt 0.03) { break }
      $len = [math]::Min($corpus.Length, [int]($len * $target / $n))
    }
    return @{ Text = $text; Tokens = $n }
  }

  function Invoke-Completion([string]$prompt) {
    # ignore_eos : force 256 tokens generes, sinon un prompt brut peut s'arreter tout de suite
    # et la vitesse de generation n'est pas mesurable.
    $body = @{ prompt = $prompt; n_predict = 256; cache_prompt = $true; ignore_eos = $true } | ConvertTo-Json
    $r = Invoke-RestMethod "$base/completion" -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' `
         -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 1800
    return $r.timings
  }

  $results = @{}
  $script:loadSec = @()
  for ($run = 1; $run -le $Runs; $run++) {
    $w = Start-VramWatch
    $srv = Start-Server
    try {
      # chauffe : la 1re requete apres chargement paie l'initialisation du GPU (graphes CUDA,
      # allocations) ; sans elle, la 1re mesure (8k) serait faussee
      $null = Invoke-RestMethod "$base/completion" -Method Post -Headers $headers -ContentType 'application/json' `
              -Body (@{ prompt = "fn main() { println!(`"warmup`"); }"; n_predict = 16; cache_prompt = $false } | ConvertTo-Json) -TimeoutSec 300
      foreach ($size in $PromptSizes) {
        $p = Get-Prompt $size "$Label-$run-$size-$(Get-Random)"
        $ask = "`n`n// Question: summarize in 5 bullet points what this code does.`n// Answer:`n"
        $cold = Invoke-Completion ($p.Text + $ask)
        $warm = Invoke-Completion ($p.Text + "`n`n// Question: list the 3 most complex functions above and why.`n// Answer:`n")
        $mtp = if ($cold.draft_n) { [math]::Round(100 * $cold.draft_n_accepted / $cold.draft_n) } else { $null }
        $key = "$size"
        if (-not $results[$key]) { $results[$key] = @() }
        $results[$key] += [pscustomobject]@{
          tokens = $p.Tokens; pp = $cold.prompt_per_second; tg = $cold.predicted_per_second; mtp = $mtp
          warm_prompt_n = $warm.prompt_n; warm_pp_ms = $warm.prompt_ms
        }
        Write-Host ("[serveur run {0}] {1} tokens : prefill {2:N0} t/s | gen {3:N1} t/s | MTP {4} | 2e requete : {5} tokens relus en {6:N1} s" -f `
          $run, $p.Tokens, $cold.prompt_per_second, $cold.predicted_per_second, $mtp, $warm.prompt_n, ($warm.prompt_ms / 1000))
      }
    } finally {
      Stop-Process -Id $srv.Id -Force -ErrorAction SilentlyContinue
      $vram = Stop-VramWatch $w
      Start-Sleep -Seconds 3
    }
    foreach ($k in $results.Keys) { $results[$k][-1] | Add-Member -NotePropertyName vram -NotePropertyValue $vram -Force }
  }

  foreach ($k in $results.Keys) {
    $r = $results[$k]
    $mtpMed = Median ([double[]]($r | Where-Object { $_.mtp -ne $null } | ForEach-Object mtp))
    $notes = "2e requete (meme debut): {0} tokens relus en {1:N1} s (mediane) | chargement {2:N0} s" -f `
      (Median ([double[]]($r.warm_prompt_n))), ((Median ([double[]]($r.warm_pp_ms))) / 1000), (Median ([double[]]$script:loadSec))
    Add-Result 'llama-server /completion' ([int](Median ([double[]]($r.tokens)))) (Median ([double[]]($r.pp))) `
      (Median ([double[]]($r.tg))) (($r | Measure-Object vram -Maximum).Maximum) $mtpMed $notes $ServerArgs
  }
}
Write-Host "Resultats ajoutes a $csv"
