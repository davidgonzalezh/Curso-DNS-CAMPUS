function Ensure-VmStoppedInteractive {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Step,

        [Parameter(Mandatory)]
        [string]$Reason,

        [int]$GracefulTimeoutSeconds = 90
    )

    while ($true) {
        $info = Get-VmInfoMap `
            -Name $Name `
            -Step "$Step-INFO" `
            -AllowMissing

        if (-not $info) {
            Write-StepOk `
                -Step $Step `
                -Message "La VM '$Name' ya no está registrada."

            return
        }

        $state = [string]$info["VMState"]

        if ($state -in @("poweroff", "aborted")) {
            Write-StepOk `
                -Step $Step `
                -Message "La VM '$Name' está detenida." `
                -Detail "VMState=$state; Motivo=$Reason"

            return
        }

        if ($state -eq "saved") {
            Write-StepWarning `
                -Step $Step `
                -Message "La VM '$Name' tiene un estado guardado." `
                -Detail $Reason

            $choice = Read-LabChoice `
                -Prompt "¿Descartar el estado guardado para continuar?" `
                -Allowed @("D", "C") `
                -Default "D"

            if ($choice -eq "C") {
                throw "El usuario canceló porque la VM '$Name' conserva un estado guardado."
            }

            Invoke-VBox `
                -Arguments @(
                    "discardstate",
                    $Name
                ) `
                -Step "$Step-DISCARD" `
                -Purpose "descartar el estado guardado de '$Name'" |
                Out-Null

            continue
        }

        if ($state -in @("running", "paused")) {
            Write-StepWarning `
                -Step $Step `
                -Message "La VM '$Name' está encendida o pausada." `
                -Detail "VMState=$state; Motivo=$Reason"

            $choice = Read-LabChoice `
                -Prompt "Seleccione: A=apagado correcto, F=forzar apagado, C=cancelar" `
                -Allowed @("A", "F", "C") `
                -Default "A"

            if ($choice -eq "C") {
                throw "El usuario canceló porque la VM '$Name' está $state."
            }

            if ($choice -eq "F") {
                if ($state -eq "paused") {
                    Invoke-VBox `
                        -Arguments @(
                            "controlvm",
                            $Name,
                            "resume"
                        ) `
                        -Step "$Step-RESUME" `
                        -Purpose "reanudar '$Name' antes de forzar el apagado" `
                        -AllowFailure |
                        Out-Null
                }

                Invoke-VBox `
                    -Arguments @(
                        "controlvm",
                        $Name,
                        "poweroff"
                    ) `
                    -Step "$Step-FORCE" `
                    -Purpose "forzar el apagado de '$Name' por decisión del usuario" |
                    Out-Null

                Start-Sleep -Seconds 2
                continue
            }

            if ($state -eq "paused") {
                Invoke-VBox `
                    -Arguments @(
                        "controlvm",
                        $Name,
                        "resume"
                    ) `
                    -Step "$Step-RESUME" `
                    -Purpose "reanudar '$Name' para solicitar un apagado ACPI" |
                    Out-Null
            }

            Invoke-VBox `
                -Arguments @(
                    "controlvm",
                    $Name,
                    "acpipowerbutton"
                ) `
                -Step "$Step-ACPI" `
                -Purpose "solicitar a Ubuntu el apagado correcto de '$Name'" `
                -AllowFailure |
                Out-Null

            $deadline = (Get-Date).AddSeconds($GracefulTimeoutSeconds)

            do {
                Start-Sleep -Seconds 2

                $current = Get-VmInfoMap `
                    -Name $Name `
                    -Step "$Step-WAIT" `
                    -AllowMissing

                if (-not $current) {
                    return
                }

                $currentState = [string]$current["VMState"]

                if ($currentState -in @("poweroff", "aborted")) {
                    Write-StepOk `
                        -Step $Step `
                        -Message "La VM '$Name' se apagó correctamente." `
                        -Detail "VMState=$currentState"

                    return
                }
            }
            while ((Get-Date) -lt $deadline)

            Write-StepWarning `
                -Step $Step `
                -Message "La VM '$Name' no se apagó dentro de $GracefulTimeoutSeconds segundos."

            $fallback = Read-LabChoice `
                -Prompt "¿Forzar ahora el apagado?" `
                -Allowed @("F", "C") `
                -Default "F"

            if ($fallback -eq "C") {
                throw "El usuario canceló después de que el apagado ACPI no terminara."
            }

            Invoke-VBox `
                -Arguments @(
                    "controlvm",
                    $Name,
                    "poweroff"
                ) `
                -Step "$Step-FORCE-AFTER-TIMEOUT" `
                -Purpose "forzar el apagado después del timeout ACPI" |
                Out-Null

            Start-Sleep -Seconds 2
            continue
        }

        if ($state -in @("starting", "stopping", "saving", "restoring")) {
            Write-StepWarning `
                -Step $Step `
                -Message "La VM '$Name' está cambiando de estado." `
                -Detail "VMState=$state"

            $choice = Read-LabChoice `
                -Prompt "¿Esperar 15 segundos y volver a comprobar?" `
                -Allowed @("E", "C") `
                -Default "E"

            if ($choice -eq "C") {
                throw "El usuario canceló mientras '$Name' estaba en estado $state."
            }

            Start-Sleep -Seconds 15
            continue
        }

        throw "Estado de VM no contemplado para corrección interactiva: $state"
    }
}
