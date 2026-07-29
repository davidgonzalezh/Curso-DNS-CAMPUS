#requires -Version 5.1
[CmdletBinding()]
param()

. "$PSScriptRoot\curso-dns-common.ps1"

Initialize-LabContext -Operation "detencion"

$exitCode = 0

try {
    $script:LabContext.VBox = Get-VBoxManagePath
    $vmName = "Curso-DNS-Lambda"

    $info = Get-VmInfoMap `
        -Name $vmName `
        -Step "T01" `
        -AllowMissing

    if (-not $info) {
        throw "La VM no está instalada."
    }

    $state = $info["VMState"]

    if ($state -eq "running") {
        Invoke-VBox `
            -Arguments @(
                "controlvm",
                $vmName,
                "acpipowerbutton"
            ) `
            -Step "T01" `
            -Purpose "solicitar apagado ACPI" |
            Out-Null

        Write-StepOk `
            -Step "T01" `
            -Message "Se solicitó el apagado correcto de Ubuntu."
    }
    elseif ($state -in @("poweroff", "aborted", "saved")) {
        Write-StepOk `
            -Step "T01" `
            -Message "La VM no está en ejecución." `
            -Detail "VMState=$state"
    }
    else {
        throw "Estado de VM no contemplado: $state"
    }
}
catch {
    $exitCode = 1
    Write-LabLog -Level "ERROR" -Step "FAIL" -Message $_.Exception.Message
}
finally {
    Finish-LabOperation -ExitCode $exitCode -Pause
}
