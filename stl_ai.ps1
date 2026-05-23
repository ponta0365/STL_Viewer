param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("list", "status", "select", "clear-selection", "add", "delete", "delete-all", "sync-defaults")]
  [string]$Command,

  [string]$Value,

  [string]$BaseUrl = "http://127.0.0.1:8000"
)

$ErrorActionPreference = "Stop"

function Invoke-Json {
  param(
    [string]$Method,
    [string]$Path,
    [object]$Body = $null,
    [bool]$Raw = $false
  )

  $uri = ($BaseUrl.TrimEnd('/') + '/' + $Path.TrimStart('/'))
  $params = @{
    Uri = $uri
    Method = $Method
    UseBasicParsing = $true
  }

  if ($null -ne $Body) {
    if ($Body -is [string]) {
      $params.Body = $Body
    } else {
      $params.Body = ($Body | ConvertTo-Json -Depth 10)
    }
    $params.ContentType = "application/json"
  }

  if ($Raw) {
    return Invoke-WebRequest @params
  }
  return Invoke-RestMethod @params
}

function Find-Model {
  param([string]$Needle)

  $models = Invoke-Json -Method GET -Path "/api/models"
  $trimmed = $Needle.Trim()
  $lower = $trimmed.ToLowerInvariant()

  foreach ($model in $models) {
    if ($model.id -eq $trimmed) { return $model }
    if ($model.name -eq $trimmed) { return $model }
    if ($model.name.ToLowerInvariant() -eq $lower) { return $model }
  }

  return $null
}

switch ($Command) {
  "list" {
    Invoke-Json -Method GET -Path "/api/models" | ConvertTo-Json -Depth 6
  }

  "status" {
    [pscustomobject]@{
      state = Invoke-Json -Method GET -Path "/api/state"
      models = Invoke-Json -Method GET -Path "/api/models"
      baseUrl = $BaseUrl
    } | ConvertTo-Json -Depth 6
  }

  "select" {
    if ([string]::IsNullOrWhiteSpace($Value)) {
      throw "select にはモデル名またはIDを指定してください"
    }
    $model = Find-Model -Needle $Value
    if (-not $model) {
      throw "指定したモデルが見つかりません: $Value"
    }
    Invoke-Json -Method PUT -Path "/api/state" -Body @{ selected_model_id = $model.id } | Out-Null
    $model.id
  }

  "clear-selection" {
    Invoke-Json -Method PUT -Path "/api/state" -Body @{ selected_model_id = $null } | Out-Null
    "selection cleared"
  }

  "add" {
    if ([string]::IsNullOrWhiteSpace($Value)) {
      throw "add には STL ファイルのパスを指定してください"
    }
    $source = Get-Item -LiteralPath $Value
    if (-not (Test-Path -LiteralPath $source.FullName -PathType Leaf)) {
      throw "ファイルが見つかりません: $Value"
    }

    $client = [System.Net.Http.HttpClient]::new()
    try {
      $content = [System.Net.Http.MultipartFormDataContent]::new()
      $bytes = [IO.File]::ReadAllBytes($source.FullName)
      $fileContent = [System.Net.Http.ByteArrayContent]::new($bytes)
      $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/octet-stream")
      $content.Add($fileContent, "files", $source.Name)

      $response = $client.PostAsync(($BaseUrl.TrimEnd('/') + "/api/models"), $content).Result
      if (-not $response.IsSuccessStatusCode) {
        throw "アップロードに失敗しました: $($response.StatusCode)"
      }
      $body = $response.Content.ReadAsStringAsync().Result
      $payload = $body | ConvertFrom-Json
      $created = @()
      $skipped = @()
      if ($payload.created) { $created = @($payload.created) }
      if ($payload.skipped) { $skipped = @($payload.skipped) }
      if ($created.Count -gt 0) {
        Invoke-Json -Method PUT -Path "/api/state" -Body @{ selected_model_id = $created[-1].id } | Out-Null
      } elseif ($skipped.Count -gt 0 -and $skipped[0].id) {
        Invoke-Json -Method PUT -Path "/api/state" -Body @{ selected_model_id = $skipped[0].id } | Out-Null
      }
      $body
    } finally {
      $client.Dispose()
    }
  }

  "delete" {
    if ([string]::IsNullOrWhiteSpace($Value)) {
      throw "delete にはモデル名またはIDを指定してください"
    }
    $model = Find-Model -Needle $Value
    if (-not $model) {
      throw "指定したモデルが見つかりません: $Value"
    }
    Invoke-Json -Method DELETE -Path "/api/models/$($model.id)" | Out-Null
    "deleted: $($model.id)"
  }

  "delete-all" {
    Invoke-Json -Method DELETE -Path "/api/models" | Out-Null
    "deleted all"
  }

  "sync-defaults" {
    "server-side storage is authoritative; no extra sync required"
  }
}
