param(
  [string]$Root = $PSScriptRoot,
  [int]$PreferredPort = 8000,
  [string]$AiCommand,
  [string]$AiValue,
  [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Root)) {
  $Root = (Get-Location).Path
}

$rootFull = [IO.Path]::GetFullPath($Root)
if ([string]::IsNullOrWhiteSpace($rootFull)) {
  $rootFull = (Get-Location).Path
}

$logDir = Join-Path $rootFull "logs"
if (-not (Test-Path -LiteralPath $logDir -PathType Container)) {
  New-Item -ItemType Directory -Path $logDir | Out-Null
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$sessionLog = Join-Path $logDir "stl_viewer_$stamp.log"
$latestPortPath = Join-Path $logDir "latest_port.txt"
$serverStdOut = Join-Path $logDir "server_$stamp.out.log"
$serverStdErr = Join-Path $logDir "server_$stamp.err.log"

function Write-Log {
  param([string]$Message)
  $line = "[{0}] {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $Message
  Add-Content -LiteralPath $sessionLog -Value $line -Encoding UTF8
}

function Test-PortFree {
  param([int]$Port)
  try {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
    $listener.Start()
    $listener.Stop()
    return $true
  } catch {
    return $false
  }
}

function Find-FreePort {
  param([int]$StartPort = 8000, [int]$EndPort = 8010)
  for ($port = $StartPort; $port -le $EndPort; $port++) {
    if (Test-PortFree -Port $port) {
      return $port
    }
  }
  throw "空きポートが見つかりませんでした"
}

function Stop-ExistingServers {
  param([string]$RootPath)

  $targets = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -match '^powershell\.exe$|^pwsh\.exe$' -and
    ($_.CommandLine -like '*server_app.py*' -or $_.CommandLine -like '*uvicorn*server_app:app*' -or $_.CommandLine -like '*local_http_server.ps1*') -and
    $_.CommandLine -like "*$RootPath*"
  }

  foreach ($target in $targets) {
    try {
      Stop-Process -Id $target.ProcessId -Force -ErrorAction SilentlyContinue
    } catch {
      # ignore already-dead processes
    }
  }
}

Stop-ExistingServers -RootPath $rootFull

$port = if (Test-PortFree -Port $PreferredPort) { $PreferredPort } else { Find-FreePort -StartPort $PreferredPort -EndPort ($PreferredPort + 20) }
Set-Content -LiteralPath $latestPortPath -Value $port -Encoding ASCII
Write-Log "Selected port: $port"

$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCmd) {
  $pythonCmd = Get-Command py -ErrorAction SilentlyContinue
}
if (-not $pythonCmd) {
  throw "Python が見つかりません"
}

$pythonExe = $pythonCmd.Source
if ([string]::IsNullOrWhiteSpace($pythonExe)) {
  $pythonExe = $pythonCmd.Path
}
if ([string]::IsNullOrWhiteSpace($pythonExe)) {
  $pythonExe = $pythonCmd.Name
}

$serverArgs = @(
  (Join-Path $rootFull 'server_app.py')
  '--host'
  '127.0.0.1'
  '--port'
  $port
)

$server = Start-Process -FilePath $pythonExe -ArgumentList $serverArgs -PassThru -RedirectStandardOutput $serverStdOut -RedirectStandardError $serverStdErr -WorkingDirectory $rootFull -WindowStyle Hidden
Write-Log "Server PID: $($server.Id)"

$url = "http://127.0.0.1:$port/"
$deadline = (Get-Date).AddSeconds(10)
while ((Get-Date) -lt $deadline) {
  try {
    Invoke-WebRequest -UseBasicParsing $url | Out-Null
    Write-Log "Server responded on $url"
    break
  } catch {
    Start-Sleep -Milliseconds 250
  }
}

if ($AiCommand) {
  $aiScript = Join-Path $rootFull "stl_ai.ps1"
  if (Test-Path -LiteralPath $aiScript -PathType Leaf) {
    Write-Log "Running CLI command: $AiCommand $AiValue"
    if ([string]::IsNullOrWhiteSpace($AiValue)) {
      & $aiScript -Command $AiCommand -BaseUrl $url
    } else {
      & $aiScript -Command $AiCommand -Value $AiValue -BaseUrl $url
    }
  } else {
    Write-Log "CLI script not found: $aiScript"
  }
}

if (-not $NoBrowser) {
  Start-Process $url
  Write-Log "Opened browser: $url"
}

Write-Host $port
return $port
