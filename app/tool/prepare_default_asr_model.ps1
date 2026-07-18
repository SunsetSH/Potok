param(
  [string]$SourceDirectory = ''
)

$ErrorActionPreference = 'Stop'
$target = Join-Path $PSScriptRoot '..\assets\models\default'
$target = [System.IO.Path]::GetFullPath($target)
$expected = @{
  'tiny-decoder.int8.onnx' = 'd2fece8dd42771f1df975c6c0445770d0c292bf7547c2cae04a6c0cc57540925'
  'tiny-encoder.int8.onnx' = 'd24fb083ae3b1041fc24e97971d60e280c9342201fbb67b0ab428a8b4a51a434'
  'tiny-tokens.txt' = 'b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126'
}

$downloadRoot = $null
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) {
  $downloadRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('potok-asr-' + [guid]::NewGuid())
  New-Item -ItemType Directory -Path $downloadRoot | Out-Null
  $archive = Join-Path $downloadRoot 'whisper-tiny.tar.bz2'
  $url = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.tar.bz2'
  Invoke-WebRequest -Uri $url -OutFile $archive
  tar -xf $archive -C $downloadRoot
  $SourceDirectory = (Get-ChildItem $downloadRoot -Directory -Filter 'sherpa-onnx-whisper-tiny*' | Select-Object -First 1).FullName
}

try {
  if (-not (Test-Path -LiteralPath $SourceDirectory -PathType Container)) {
    throw "Model source directory not found: $SourceDirectory"
  }
  New-Item -ItemType Directory -Force -Path $target | Out-Null
  foreach ($entry in $expected.GetEnumerator()) {
    $source = Join-Path $SourceDirectory $entry.Key
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
      throw "Missing model file: $($entry.Key)"
    }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash.ToLowerInvariant()
    if ($actual -ne $entry.Value) {
      throw "SHA-256 mismatch: $($entry.Key)"
    }
    Copy-Item -LiteralPath $source -Destination (Join-Path $target $entry.Key) -Force
  }
  Write-Output "Default ASR model prepared in $target"
} finally {
  if ($null -ne $downloadRoot -and (Test-Path -LiteralPath $downloadRoot)) {
    Remove-Item -LiteralPath $downloadRoot -Recurse -Force
  }
}
