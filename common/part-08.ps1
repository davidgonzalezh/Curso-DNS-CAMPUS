function Resolve-ListeningPortConflictsInteractive {
    param(
        [Parameter(Mandatory)]
        [int[]]$Ports,

        [Parameter(Mandatory)]
        [string]$Step
    )

    while ($true) {
        $listeners = @(Get-ListeningPortOwners -Ports $Ports)

        if (-not $listeners) {
            Write-StepOk `
                -Step $Step `
                -Message "Los puertos requeridos están libres." `
                -Detail "Ports=$($Ports -join ',')"

            return
        }

        $detail = (
            $listeners |
                Format-Table -AutoSize |
                Out-String
        ).Trim()

        Write-StepWarning `
            -Step $Step `
            -Message "Uno o más puertos requeridos están ocupados." `
            -Detail $detail

        $choice = Read-LabChoice `
            -Prompt "Seleccione: R=reintentar después de cerrar el proceso, T=terminar los procesos listados, C=cancelar" `
            -Allowed @("R", "T", "C") `
            -Default "R"

        if ($choice -eq "C") {
            throw "Los puertos $($Ports -join ', ') continúan ocupados."
        }

        if ($choice -eq "R") {
            continue
        }

        foreach ($listener in $listeners) {
            if ($listener.ProcessId -eq $PID) {
                throw "El proceso actual aparece como propietario del puerto $($listener.Port); no se terminará a sí mismo."
            }

            Write-StepWarning `
                -Step "$Step-STOP" `
                -Message "Terminando el proceso confirmado por el usuario." `
                -Detail (
                    "PID=$($listener.ProcessId); " +
                    "Process=$($listener.ProcessName); Port=$($listener.Port)"
                )

            Stop-Process `
                -Id $listener.ProcessId `
                -Force `
                -ErrorAction Stop
        }

        Start-Sleep -Seconds 2
    }
}
