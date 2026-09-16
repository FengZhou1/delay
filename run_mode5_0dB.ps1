<#
  Run R10 CTS mode 5 (isotropic quasi-omni) at 0 dB from PowerShell, with a
  single worker, while the existing 4-worker run keeps going.

  Usage:
      powershell -ExecutionPolicy Bypass -File .\run_mode5_0dB.ps1

  Results land in  R10_results\20260914_201159\result5\qo_iso_0dB\
  (the run that is going on right now writes result5\qo_iso_-9dB\, so the two
  never collide).

  R10_N_WORKERS is a runtime-only knob: it is stripped from the config hash, so
  the run identity and its resume behaviour are unchanged.
#>

$ErrorActionPreference = 'Stop'

$ProjectRoot = 'C:\Users\Administrator\Documents\delay'
$MatlabExe   = 'D:\Software\Matlab\bin\matlab.exe'
$RunRoot     = Join-Path $ProjectRoot 'R10_results\20260914_201159'
$LogFile     = Join-Path $RunRoot  'result5\qo_iso_0dB_run.log'

if (-not (Test-Path -LiteralPath $RunRoot))  { throw "Missing run directory: $RunRoot" }
if (-not (Test-Path -LiteralPath $MatlabExe)){ throw "MATLAB not found: $MatlabExe" }

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogFile) | Out-Null

$env:R10_N_WORKERS = '1'
# $env:R10_PARALLEL = '0'   # uncomment for fully serial (no parpool at all)

$code = "cd('$ProjectRoot'); run_R10_cts_modes('txop',{},5,'$RunRoot',[162.5 650],[0]);"

Write-Host 'Launching MATLAB: R10 CTS mode 5 @ 0 dB, 1 worker' -ForegroundColor Cyan
Write-Host "  project : $ProjectRoot"
Write-Host "  output  : $RunRoot\result5\qo_iso_0dB"
Write-Host "  log     : $LogFile"
Write-Host ''

& $MatlabExe -batch $code 2>&1 | Tee-Object -FilePath $LogFile -Append

Write-Host ''
Write-Host "MATLAB exited with code $LASTEXITCODE" -ForegroundColor Yellow