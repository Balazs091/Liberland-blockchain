$ErrorActionPreference = "Stop"

$contracts = Get-Content "scripts/frontend-abi-contracts.txt"
$outputDirectory = "frontend-export/abis"
$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
foreach ($contract in $contracts) {
    $abi = (& forge inspect $contract abi --json) -join [Environment]::NewLine
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to export ABI for $contract"
    }

    $null = $abi | ConvertFrom-Json
    $document = '{"abi":' + $abi + '}' + [Environment]::NewLine
    [System.IO.File]::WriteAllText((Join-Path $outputDirectory "$contract.json"), $document, $utf8WithoutBom)
}
