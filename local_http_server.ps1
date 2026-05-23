param(
  [int]$Port = 8000,
  [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = "Stop"

function Get-ContentType {
  param([string]$Path)

  switch ([IO.Path]::GetExtension($Path).ToLowerInvariant()) {
    ".html" { "text/html; charset=utf-8" }
    ".htm" { "text/html; charset=utf-8" }
    ".js" { "application/javascript; charset=utf-8" }
    ".css" { "text/css; charset=utf-8" }
    ".json" { "application/json; charset=utf-8" }
    ".svg" { "image/svg+xml" }
    ".png" { "image/png" }
    ".jpg" { "image/jpeg" }
    ".jpeg" { "image/jpeg" }
    ".webp" { "image/webp" }
    ".ico" { "image/x-icon" }
    ".stl" { "application/sla" }
    default { "application/octet-stream" }
  }
}

function Send-Response {
  param(
    [System.Net.Sockets.NetworkStream]$Stream,
    [int]$StatusCode,
    [string]$StatusText,
    [byte[]]$Body,
    [string]$ContentType = "text/plain; charset=utf-8"
  )

  $header = @(
    "HTTP/1.1 $StatusCode $StatusText"
    "Content-Type: $ContentType"
    "Content-Length: $($Body.Length)"
    "Connection: close"
    ""
    ""
  ) -join "`r`n"

  $headerBytes = [Text.Encoding]::ASCII.GetBytes($header)
  $Stream.Write($headerBytes, 0, $headerBytes.Length)
  if ($Body.Length -gt 0) {
    $Stream.Write($Body, 0, $Body.Length)
  }
  $Stream.Flush()
}

$directoryListingTemplate = @'
<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <title>Directory listing</title>
  <style>
    body { font-family: sans-serif; padding: 24px; }
    a { display: block; margin: 8px 0; }
  </style>
</head>
<body>
  <h1>Directory listing</h1>
  <div id="list">__LIST__</div>
</body>
</html>
'@

$rootFull = [IO.Path]::GetFullPath($Root)
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
$listener.Start()

try {
  Write-Host "Serving $rootFull on http://127.0.0.1:$Port/"

  while ($true) {
    $client = $listener.AcceptTcpClient()
    try {
      $stream = $client.GetStream()
      $reader = [System.IO.StreamReader]::new($stream, [Text.Encoding]::ASCII, $false, 1024, $true)

      $requestLine = $reader.ReadLine()
      if ([string]::IsNullOrWhiteSpace($requestLine)) {
        continue
      }

      while ($true) {
        $line = $reader.ReadLine()
        if ([string]::IsNullOrEmpty($line)) {
          break
        }
      }

      $parts = $requestLine.Split(' ')
      if ($parts.Length -lt 2) {
        continue
      }

      $rawPath = $parts[1]
      $path = [Uri]::UnescapeDataString($rawPath.Split('?')[0]).TrimStart('/')
      if ([string]::IsNullOrWhiteSpace($path)) {
        $path = "STL-viewer.html"
      }

      $relativePath = $path.Replace('/', [IO.Path]::DirectorySeparatorChar)
      $candidate = [IO.Path]::GetFullPath((Join-Path $rootFull $relativePath))

      if (-not $candidate.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
        $body = [Text.Encoding]::UTF8.GetBytes("403 Forbidden")
        Send-Response -Stream $stream -StatusCode 403 -StatusText "Forbidden" -Body $body
        continue
      }

      if (Test-Path -LiteralPath $candidate -PathType Container) {
        $indexHtml = Join-Path $candidate "index.html"
        $indexHtm = Join-Path $candidate "index.htm"

        if (Test-Path -LiteralPath $indexHtml -PathType Leaf) {
          $bytes = [IO.File]::ReadAllBytes($indexHtml)
          Send-Response -Stream $stream -StatusCode 200 -StatusText "OK" -Body $bytes -ContentType "text/html; charset=utf-8"
          continue
        }

        if (Test-Path -LiteralPath $indexHtm -PathType Leaf) {
          $bytes = [IO.File]::ReadAllBytes($indexHtm)
          Send-Response -Stream $stream -StatusCode 200 -StatusText "OK" -Body $bytes -ContentType "text/html; charset=utf-8"
          continue
        }

        $items = Get-ChildItem -LiteralPath $candidate | Sort-Object Name | ForEach-Object {
          $name = [System.Net.WebUtility]::HtmlEncode($_.Name)
          $href = if ([string]::IsNullOrWhiteSpace($path)) { $_.Name } else { ($path.TrimEnd('/') + '/' + $_.Name) }
          $href = [System.Net.WebUtility]::HtmlEncode($href)
          "<a href=""$href"">$name</a>"
        }
        $bodyText = $directoryListingTemplate.Replace('__LIST__', ($items -join "`r`n"))
        $bytes = [Text.Encoding]::UTF8.GetBytes($bodyText)
        Send-Response -Stream $stream -StatusCode 200 -StatusText "OK" -Body $bytes -ContentType "text/html; charset=utf-8"
      } elseif (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $bytes = [IO.File]::ReadAllBytes($candidate)
        Send-Response -Stream $stream -StatusCode 200 -StatusText "OK" -Body $bytes -ContentType (Get-ContentType $candidate)
      } else {
        $body = [Text.Encoding]::UTF8.GetBytes("404 Not Found")
        Send-Response -Stream $stream -StatusCode 404 -StatusText "Not Found" -Body $body
      }
    } catch {
      try {
        $body = [Text.Encoding]::UTF8.GetBytes($_.Exception.Message)
        Send-Response -Stream $stream -StatusCode 500 -StatusText "Internal Server Error" -Body $body
      } catch {
        # ignore secondary write failures
      }
    } finally {
      if ($client) {
        $client.Close()
      }
    }
  }
} finally {
  $listener.Stop()
}
