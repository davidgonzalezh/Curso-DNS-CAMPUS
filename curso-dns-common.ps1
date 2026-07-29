#requires -Version 5.1

$commonRoot = Join-Path $PSScriptRoot "common"

foreach ($part in @(
    "part-01.ps1",
    "part-02.ps1",
    "part-03.ps1",
    "part-04.ps1",
    "part-05.ps1",
    "part-06.ps1",
    "part-07.ps1",
    "part-08.ps1",
    "part-09.ps1",
    "part-10.ps1",
    "part-11.ps1"
)) {
    $partPath = Join-Path $commonRoot $part

    if (-not (Test-Path -LiteralPath $partPath)) {
        throw "Falta el componente común requerido: $partPath"
    }

    . $partPath
}
