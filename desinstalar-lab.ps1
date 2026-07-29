#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Elevated
)

. "$PSScriptRoot\curso-dns-common.ps1"

Initialize-LabContext -Operation "desinstalacion"

$exitCode = 0

try {
    if (-not $Elevated -and -not (Test-IsAdministrator)) {
        Restart-Elevated -ScriptPath $PSCommandPath
    }

    $script:LabContext.VBox = Get-VBoxManagePath

    $vmName = "Curso-DNS-Lambda"
    $stateRoot = Join-Path $env:ProgramData "CursoDNSCampus"
    $statePath = Join-Path $stateRoot "lab-state.json"

    Write-StepStart `
        -Step "U01" `
        -Purpose "Identificar los recursos pertenecientes al laboratorio."

    $state = Read-LabState -StatePath $statePath
    $vmInfo = Get-VmInfoMap `
        -Name $vmName `
        -Step "U01-VM" `
        -AllowMissing

    if (-not $state -and -not $vmInfo) {
        throw @"
No existe una instalación administrada ni una VM llamada '$vmName'.

No se eliminarán interfaces o VM ajenas.
Ejecute DIAGNOSTICAR_LAB.cmd y entregue el log al instructor si esperaba encontrar una instalación.
"@
    }

    $legacyMode = $false

    if (-not $state -and $vmInfo) {
        $legacyMode = $true

        Write-StepWarning `
            -Step "U01" `
            -Message "Se detectó una instalación parcial sin archivo de estado." `
            -Detail "VM=$vmName; Estado=$($vmInfo["VMState"])"
    }

    if ($state) {
        Write-StepOk `
            -Step "U01" `
            -Message "Estado administrado encontrado." `
            -Detail (
                "Stage=$($state.Stage); VM=$($state.VmName); " +
                "HostOnly=$($state.HostOnlyInterfaceName)"
            )
    }

    $confirmation = if ($legacyMode) {
        "DESINSTALAR-LEGACY"
    }
    else {
        "DESINSTALAR"
    }

    $entered = Read-Host "Escriba $confirmation para continuar"

    if ($entered -ne $confirmation) {
        throw "Operación cancelada por el usuario."
    }

    Write-StepStart `
        -Step "U02" `
        -Purpose "Detener la VM en cualquier estado compatible."

    if ($vmInfo) {
        $vmState = $vmInfo["VMState"]

        if ($vmState -eq "paused") {
            Invoke-VBox `
                -Arguments @(
                    "controlvm",
                    $vmName,
                    "resume"
                ) `
                -Step "U02-RESUME" `
                -Purpose "reanudar la VM pausada antes de apagarla" |
                Out-Null

            $vmState = "running"
        }

        if ($vmState -eq "running") {
            Invoke-VBox `
                -Arguments @(
                    "controlvm",
                    $vmName,
                    "acpipowerbutton"
                ) `
                -Step "U02-ACPI" `
                -Purpose "solicitar apagado ACPI" `
                -AllowFailure |
                Out-Null

            $deadline = (Get-Date).AddSeconds(60)

            do {
                Start-Sleep -Seconds 2
                $vmInfo = Get-VmInfoMap `
                    -Name $vmName `
                    -Step "U02-WAIT" `
                    -AllowMissing

                if (-not $vmInfo) {
                    break
                }

                $vmState = $vmInfo["VMState"]
            }
            while ($vmState -eq "running" -and (Get-Date) -lt $deadline)

            if ($vmState -eq "running") {
                Write-StepWarning `
                    -Step "U02" `
                    -Message "Ubuntu no terminó el apagado ACPI en 60 segundos; se forzará el apagado."

                Invoke-VBox `
                    -Arguments @(
                        "controlvm",
                        $vmName,
                        "poweroff"
                    ) `
                    -Step "U02-FORCE" `
                    -Purpose "forzar apagado de la VM" |
                    Out-Null
            }
        }
        elseif ($vmState -eq "saved") {
            Invoke-VBox `
                -Arguments @(
                    "discardstate",
                    $vmName
                ) `
                -Step "U02-DISCARD" `
                -Purpose "descartar estado guardado antes de eliminar" |
                Out-Null
        }
        elseif ($vmState -in @("poweroff", "aborted")) {
            Write-StepOk `
                -Step "U02" `
                -Message "La VM ya está fuera de ejecución." `
                -Detail "VMState=$vmState"
        }
        else {
            throw "Estado de VM no contemplado para desinstalar: $vmState"
        }
    }

    Write-StepStart `
        -Step "U03" `
        -Purpose "Eliminar reglas NAT y desconectar la red privada de la VM."

    $vmInfo = Get-VmInfoMap `
        -Name $vmName `
        -Step "U03-VM" `
        -AllowMissing

    if ($vmInfo) {
        $existingRules = @(Get-ForwardingRules -VmInfo $vmInfo)

        $ruleSummary = (
            $existingRules |
                ForEach-Object {
                    "$($_.Name):$($_.HostIp):$($_.HostPort)->$($_.GuestPort)"
                }
        ) -join "; "

        Write-LabLog `
            -Level "INFO" `
            -Step "U03" `
            -Message "Las reglas NAT pertenecen al archivo de configuración de la VM." `
            -Detail "Reglas=$ruleSummary; se eliminarán con unregistervm --delete."

        Invoke-VBox `
            -Arguments @(
                "modifyvm",
                $vmName,
                "--nic2=none"
            ) `
            -Step "U03-NIC2" `
            -Purpose "desconectar Adaptador 2 antes de retirar la interfaz Host-Only" `
            -AllowFailure |
            Out-Null

        Write-StepOk `
            -Step "U03" `
            -Message "Adaptador 2 procesado; las reglas NAT se retirarán al borrar la VM."
    }

    Write-StepStart `
        -Step "U04" `
        -Purpose "Eliminar la VM importada, discos, configuración y logs."

    $vmInfo = Get-VmInfoMap `
        -Name $vmName `
        -Step "U04-VM" `
        -AllowMissing

    if ($vmInfo) {
        Invoke-VBox `
            -Arguments @(
                "unregistervm",
                $vmName,
                "--delete"
            ) `
            -Step "U04-DELETE" `
            -Purpose "eliminar completamente la VM '$vmName'" `
            -LogOutput |
            Out-Null
    }

    $vmAfter = Get-VmInfoMap `
        -Name $vmName `
        -Step "U04-VERIFY" `
        -AllowMissing

    if ($vmAfter) {
        throw "La VM todavía aparece registrada después de unregistervm --delete."
    }

    Write-StepOk `
        -Step "U04" `
        -Message "VM eliminada."

    Write-StepStart `
        -Step "U05" `
        -Purpose "Eliminar la interfaz Host-Only creada por el laboratorio."

    $interfaces = @(Get-HostOnlyInterfaces -Step "U05-LIST")
    $candidate = $null

    if ($state) {
        if ($state.HostOnlyInterfaceGuid) {
            $candidate = $interfaces |
                Where-Object {
                    $_.Guid -eq $state.HostOnlyInterfaceGuid
                } |
                Select-Object -First 1
        }

        if (-not $candidate -and $state.HostOnlyInterfaceName) {
            $candidate = $interfaces |
                Where-Object {
                    $_.Name -eq $state.HostOnlyInterfaceName
                } |
                Select-Object -First 1
        }
    }
    elseif ($legacyMode) {
        $candidate = $interfaces |
            Where-Object {
                $_.IPAddress -eq "192.168.10.1" -and
                $_.NetworkMask -eq "255.255.255.0"
            } |
            Select-Object -First 1
    }

    if ($candidate) {
        $users = @()

        foreach ($otherVmName in (Get-RegisteredVmNames -Step "U05-VMS")) {
            $otherInfo = Get-VmInfoMap `
                -Name $otherVmName `
                -Step "U05-SCAN"

            foreach ($key in $otherInfo.Keys) {
                if ($key -match '^hostonlyadapter\d+$' -and
                    $otherInfo[$key] -eq $candidate.Name) {

                    $users += $otherVmName
                }
            }
        }

        if ($users) {
            throw "La interfaz '$($candidate.Name)' todavía está conectada a: $($users -join ', '). No se eliminó."
        }

        Invoke-VBox `
            -Arguments @(
                "dhcpserver",
                "remove",
                "--interface=$($candidate.Name)"
            ) `
            -Step "U05-DHCP" `
            -Purpose "eliminar DHCP asociado, si existe" `
            -AllowFailure |
            Out-Null

        Invoke-VBox `
            -Arguments @(
                "hostonlyif",
                "remove",
                $candidate.Name
            ) `
            -Step "U05-REMOVE" `
            -Purpose "eliminar la interfaz Host-Only '$($candidate.Name)'" |
            Out-Null

        $remaining = @(
            Get-HostOnlyInterfaces -Step "U05-VERIFY"
        ) |
            Where-Object {
                $_.Guid -eq $candidate.Guid
            }

        if ($remaining) {
            throw "VirtualBox todavía lista la interfaz Host-Only después de eliminarla."
        }

        Write-StepOk `
            -Step "U05" `
            -Message "Interfaz Host-Only eliminada." `
            -Detail "Name=$($candidate.Name); GUID=$($candidate.Guid)"
    }
    else {
        Write-StepWarning `
            -Step "U05" `
            -Message "No se encontró una interfaz Host-Only asociada; puede haber sido eliminada previamente."
    }

    Write-StepStart `
        -Step "U06" `
        -Purpose "Eliminar el estado del instalador y verificar la limpieza."

    if (Test-Path -LiteralPath $stateRoot) {
        Remove-Item `
            -LiteralPath $stateRoot `
            -Recurse `
            -Force
    }

    if (Test-Path -LiteralPath $stateRoot) {
        throw "No fue posible eliminar $stateRoot."
    }

    $remainingListeners = Get-ListeningPortOwners -Ports @(2222, 8888)

    if ($remainingListeners) {
        Write-StepWarning `
            -Step "U06" `
            -Message "Los puertos 2222 o 8888 siguen ocupados por otro proceso." `
            -Detail (
                $remainingListeners |
                    Format-Table -AutoSize |
                    Out-String
            )
    }

    Write-StepOk `
        -Step "U06" `
        -Message "Estado del instalador eliminado y verificación terminada."

    Remove-LabKnownHostsEntries `
        -Step "U07-KNOWN-HOSTS"

    Write-Host ""
    Write-Host "DESINSTALACIÓN COMPLETADA" -ForegroundColor Green
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
    Write-Host "ERROR DE DESINSTALACIÓN" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
finally {
    Finish-LabOperation `
        -ExitCode $exitCode `
        -Pause
}
