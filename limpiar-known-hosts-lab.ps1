#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Elevated
)

. "$PSScriptRoot\curso-dns-common.ps1"

Initialize-LabContext -Operation "limpieza-known-hosts"

$exitCode = 0

try {
    if (-not $Elevated -and -not (Test-IsAdministrator)) {
        Restart-Elevated -ScriptPath $PSCommandPath
    }

    Remove-LabKnownHostsEntries `
        -Step "KH01"

    Write-Host ""
    Write-Host "LIMPIEZA SSH COMPLETADA" -ForegroundColor Green
}
catch {
    $exitCode = 1

    Write-LabLog `
        -Level "ERROR" `
        -Step "FAIL" `
        -Message $_.Exception.Message `
        -Detail (
            "Category=$($_.CategoryInfo.Category); " +
            "ScriptStack=$($_.ScriptStackTrace)"
        )

    Write-Host ""
    Write-Host "ERROR DE LIMPIEZA SSH" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
finally {
    Finish-LabOperation `
        -ExitCode $exitCode `
        -Pause
}
