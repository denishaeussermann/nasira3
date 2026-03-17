Set-StrictMode -Version Latest

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

$candidateFiles = @(
    (Join-Path $projectRoot "files.txt"),
    (Join-Path $projectRoot "assets\metacom\files.txt")
)

$txtPath = $null
foreach ($candidate in $candidateFiles) {
    if (Test-Path $candidate) {
        $txtPath = $candidate
        break
    }
}

if (-not $txtPath) {
    Write-Error "Keine files.txt gefunden. Erwartet an: $($candidateFiles -join ' oder ')"
    exit 1
}

$outPath = Join-Path $projectRoot "assets\metacom_index.json"

$lines = Get-Content $txtPath -Encoding UTF8 | Where-Object {
    $_ -and $_.Trim() -ne ""
}

$items = New-Object System.Collections.Generic.List[object]
$byKey = @{}
$categories = New-Object System.Collections.Generic.HashSet[string]

foreach ($line in $lines) {
    $raw = $line.Trim().Trim('"')

    if ($raw -notmatch '\.(jpg|jpeg|png|webp)$') {
        continue
    }

    $relativeWindows = $raw -replace '/', '\'
    $relativeUnix = $relativeWindows -replace '\\', '/'

    $fileName = Split-Path $relativeWindows -Leaf
    $name = [System.IO.Path]::GetFileNameWithoutExtension($fileName)

    $segments = $relativeWindows -split '\\'
    $category = if ($segments.Length -gt 1) { $segments[0] } else { "OhneKategorie" }

    $null = $categories.Add($category)

    $key = $name.ToLowerInvariant()
    $id = ($relativeUnix.ToLowerInvariant() -replace '[^a-z0-9/_\.-]', '_')

    $item = [PSCustomObject][ordered]@{
        id = $id
        key = $key
        label = $name
        fileName = $fileName
        category = $category
        relativePath = $relativeUnix
        assetPath = "assets/metacom/$relativeUnix"
    }

    $items.Add($item)

    if (-not $byKey.ContainsKey($key)) {
        $byKey[$key] = New-Object System.Collections.Generic.List[object]
    }

    $byKey[$key].Add($item)
}

$categoryList = @($categories | Sort-Object)

$index = [PSCustomObject][ordered]@{
    generatedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
    sourceFile = [System.IO.Path]::GetFileName($txtPath)
    count = $items.Count
    categories = $categoryList
    items = $items
    byKey = $byKey
}

$json = $index | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($outPath, $json, [System.Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "Fertig."
Write-Host "Quelle: $txtPath"
Write-Host "JSON:   $outPath"
Write-Host "Anzahl: $($items.Count)"
Write-Host "Kategorien: $($categoryList.Count)"
Write-Host ""
