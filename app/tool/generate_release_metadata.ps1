param(
    [string]$OutputDirectory = "build/release-metadata"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Push-Location $projectRoot
try {
    $resolvedOutput = [System.IO.Path]::GetFullPath((Join-Path $projectRoot $OutputDirectory))
    New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null

    $flutterCommand = Get-Command flutter -ErrorAction Stop
    $flutterBin = Split-Path -Parent $flutterCommand.Source
    $bundledDart = Join-Path $flutterBin "cache/dart-sdk/bin/dart.exe"
    $dartCommand = if (Test-Path -LiteralPath $bundledDart) {
        $bundledDart
    } else {
        (Get-Command dart -ErrorAction Stop).Source
    }
    $depsText = (& $dartCommand pub deps --json | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw "dart pub deps failed with exit code $LASTEXITCODE"
    }
    $deps = $depsText | ConvertFrom-Json
    $byName = @{}
    foreach ($package in $deps.packages) {
        $byName[$package.name] = $package
    }

    $root = $byName[$deps.root]
    $rootRef = "pkg:pub/$($root.name)@$($root.version)"
    $components = @(
        foreach ($package in $deps.packages | Where-Object { $_.kind -ne "root" } | Sort-Object name) {
            $reference = "pkg:pub/$($package.name)@$($package.version)"
            [ordered]@{
                type = "library"
                name = $package.name
                version = $package.version
                scope = if ($package.kind -eq "dev") { "optional" } else { "required" }
                "bom-ref" = $reference
                purl = $reference
                properties = @(
                    [ordered]@{ name = "dev.dart.pub.kind"; value = [string]$package.kind },
                    [ordered]@{ name = "dev.dart.pub.source"; value = [string]$package.source }
                )
            }
        }
    )
    $dependencyGraph = @(
        foreach ($package in $deps.packages | Sort-Object name) {
            $reference = if ($package.kind -eq "root") {
                $rootRef
            } else {
                "pkg:pub/$($package.name)@$($package.version)"
            }
            $children = @(
                foreach ($dependencyName in $package.dependencies | Sort-Object) {
                    if ($byName.ContainsKey($dependencyName)) {
                        $dependency = $byName[$dependencyName]
                        "pkg:pub/$($dependency.name)@$($dependency.version)"
                    }
                }
            )
            [ordered]@{ ref = $reference; dependsOn = $children }
        }
    )
    $bom = [ordered]@{
        bomFormat = "CycloneDX"
        specVersion = "1.5"
        serialNumber = "urn:uuid:$([guid]::NewGuid())"
        version = 1
        metadata = [ordered]@{
            timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            tools = [ordered]@{
                components = @(
                    [ordered]@{
                        type = "application"
                        name = "Potok release metadata generator"
                        version = "1"
                    }
                )
            }
            component = [ordered]@{
                type = "application"
                name = $root.name
                version = $root.version
                "bom-ref" = $rootRef
                purl = $rootRef
            }
        }
        components = $components
        dependencies = $dependencyGraph
    }

    $sbomPath = Join-Path $resolvedOutput "potok.cdx.json"
    $bom | ConvertTo-Json -Depth 12 | Set-Content -Encoding utf8 $sbomPath

    $artifactFiles = @()
    $apkDirectory = Join-Path $projectRoot "build/app/outputs/flutter-apk"
    if (Test-Path -LiteralPath $apkDirectory) {
        $artifactFiles += Get-ChildItem -LiteralPath $apkDirectory -File -Filter "*-release.apk"
    }
    $windowsDirectory = Join-Path $projectRoot "build/windows/x64/runner/Release"
    if (Test-Path -LiteralPath $windowsDirectory) {
        $artifactFiles += Get-ChildItem -LiteralPath $windowsDirectory -File -Recurse
    }
    $hashLines = @()
    foreach ($artifact in $artifactFiles | Sort-Object FullName -Unique) {
        if (-not $artifact.FullName.StartsWith($projectRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Artifact escaped project root"
        }
        $relativePath = $artifact.FullName.Substring($projectRoot.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $artifact.FullName).Hash.ToLowerInvariant()
        $hashLines += "$hash  $relativePath"
    }
    $sbomHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sbomPath).Hash.ToLowerInvariant()
    $hashLines += "$sbomHash  $OutputDirectory/potok.cdx.json"
    $hashLines | Set-Content -Encoding ascii (Join-Path $resolvedOutput "SHA256SUMS.txt")

    Write-Output "Generated $sbomPath"
    Write-Output "Generated $(Join-Path $resolvedOutput 'SHA256SUMS.txt')"
} finally {
    Pop-Location
}
