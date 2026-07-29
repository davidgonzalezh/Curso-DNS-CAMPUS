#requires -Version 5.1
[CmdletBinding()]
param()

. "$PSScriptRoot\curso-dns-common.ps1"

Initialize-LabContext -Operation "inicio"

$exitCode = 0

try {
    $script:LabContext.VBox = Get-VBoxManagePath
    $vmName = "Curso-DNS-Lambda"

    $info = Get-VmInfoMap `
        -Name $vmName `
        -Step "S01" `
        -AllowMissing

    if (-not $info) {
        throw "La VM no está instalada. Ejecute INSTALAR_LAB.cmd."
    }

    $state = $info["VMState"]

    if ($state -eq "running") {
        Write-StepOk -Step "S01" -Message "La VM ya está iniciada."
    }
    elseif ($state -in @("poweroff", "aborted", "saved")) {
        if ($state -eq "saved") {
            Write-StepWarning `
                -Step "S01" `
                -Message "La VM tiene un estado guardado; VirtualBox intentará reanudarlo."
        }

        Invoke-VBox `
            -Arguments @(
                "startvm",
                $vmName,
                "--type=headless"
            ) `
            -Step "S01" `
            -Purpose "iniciar la VM en modo Headless" |
            Out-Null
    }
    else {
        throw "Estado de VM no contemplado: $state"
    }

    if (-not (Wait-TcpPort -HostName "127.0.0.1" -Port 2222 -TimeoutSeconds 180)) {
        throw "La VM inició, pero SSH no respondió en 127.0.0.1:2222."
    }

    if (-not (Wait-TcpPort -HostName "127.0.0.1" -Port 8888 -TimeoutSeconds 180)) {
        throw "La VM inició, pero WebSSH no respondió en 180 segundos."
    }

    Start-Process "http://127.0.0.1:8888/"
    Write-StepOk -Step "S02" -Message "WebSSH está disponible."
}
catch {
    $exitCode = 1
    Write-LabLog -Level "ERROR" -Step "FAIL" -Message $_.Exception.Message
}
finally {
    Finish-LabOperation -ExitCode $exitCode -Pause
}
