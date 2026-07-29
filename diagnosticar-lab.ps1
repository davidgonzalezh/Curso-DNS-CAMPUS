#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Elevated
)

. "$PSScriptRoot\curso-dns-common.ps1"

Initialize-LabContext -Operation "diagnostico"

$exitCode = 0

try {
    if (-not $Elevated -and -not (Test-IsAdministrator)) {
        Restart-Elevated -ScriptPath $PSCommandPath
    }

    $script:LabContext.VBox = Get-VBoxManagePath

    $vmName = "Curso-DNS-Lambda"
    $ovaPath = Join-Path $PSScriptRoot "Curso_DNS_Lambda_1.1.ova"
    $hashPath = Join-Path $PSScriptRoot "SHA256SUMS.txt"
    $statePath = Join-Path $env:ProgramData "CursoDNSCampus\lab-state.json"

    Write-StepStart -Step "D01" -Purpose "Registrar entorno de Windows y VirtualBox."

    $version = Invoke-VBox `
        -Arguments @("--version") `
        -Step "D01-VERSION" `
        -Purpose "obtener versión de VirtualBox"

    Write-StepOk `
        -Step "D01" `
        -Message "Entorno registrado." `
        -Detail "VBox=$($script:LabContext.VBox); Version=$($version.StdOut)"

    Write-StepStart -Step "D02" -Purpose "Verificar archivos, tamaño y SHA-256."

    $fileSummary = Get-ChildItem -LiteralPath $PSScriptRoot |
        Select-Object Name, Length, LastWriteTime

    Write-LabLog `
        -Level "INFO" `
        -Step "D02" `
        -Message "Archivos encontrados." `
        -Detail (($fileSummary | Format-Table -AutoSize | Out-String).Trim())

    if (Test-Path -LiteralPath $ovaPath) {
        $actual = (
            Get-FileHash `
                -LiteralPath $ovaPath `
                -Algorithm SHA256
        ).Hash

        $expected = ""

        if (Test-Path -LiteralPath $hashPath) {
            $expected = (
                (
                    Get-Content -LiteralPath $hashPath |
                        Select-Object -First 1
                ) -split "\s+"
            )[0]
        }

        $level = if ($actual -eq $expected) { "OK" } else { "WARN" }

        Write-LabLog `
            -Level $level `
            -Step "D02" `
            -Message "Resultado SHA-256." `
            -Detail "Esperado=$expected; Calculado=$actual"
    }

    Write-StepStart -Step "D03" -Purpose "Inspeccionar la OVA."

    if (Test-Path -LiteralPath $ovaPath) {
        $dryRun = Invoke-VBox `
            -Arguments @(
                "import",
                $ovaPath,
                "--dry-run"
            ) `
            -Step "D03" `
            -Purpose "realizar dry-run de la OVA" `
            -AllowFailure

        Write-LabLog `
            -Level $(if ($dryRun.ExitCode -eq 0) { "OK" } else { "ERROR" }) `
            -Step "D03" `
            -Message "Dry-run de la OVA." `
            -Detail (
                "ExitCode=$($dryRun.ExitCode); " +
                "Explanation=$($dryRun.Explanation); " +
                "STDOUT=$($dryRun.StdOut); STDERR=$($dryRun.StdErr)"
            )
    }

    Write-StepStart -Step "D04" -Purpose "Registrar VM y reglas de red relevantes."

    foreach ($name in (Get-RegisteredVmNames -Step "D04-LIST")) {
        $info = Get-VmInfoMap `
            -Name $name `
            -Step "D04-INFO"

        $rules = @(Get-ForwardingRules -VmInfo $info)

        $summary = [ordered]@{
            Name = $name
            UUID = $info["UUID"]
            State = $info["VMState"]
            Nic1 = $info["nic1"]
            Nic2 = $info["nic2"]
            HostOnlyAdapter2 = $info["hostonlyadapter2"]
            Forwardings = (
                $rules |
                    ForEach-Object {
                        "$($_.Name):$($_.HostIp):$($_.HostPort)->$($_.GuestPort)"
                    }
            ) -join "; "
        }

        Write-LabLog `
            -Level "INFO" `
            -Step "D04" `
            -Message "VM registrada." `
            -Detail (($summary | ConvertTo-Json -Compress))
    }

    Write-StepStart -Step "D05" -Purpose "Registrar interfaces Host-Only y dirección 192.168.10.0/24."

    foreach ($interface in (Get-HostOnlyInterfaces -Step "D05-HOSTONLY")) {
        Write-LabLog `
            -Level "INFO" `
            -Step "D05" `
            -Message "Interfaz Host-Only." `
            -Detail (
                "Name=$($interface.Name); GUID=$($interface.Guid); " +
                "IP=$($interface.IPAddress); Mask=$($interface.NetworkMask); " +
                "Status=$($interface.Status)"
            )
    }

    $addresses = Get-NetIPAddress `
        -AddressFamily IPv4 `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -like "192.168.10.*"
        }

    Write-LabLog `
        -Level "INFO" `
        -Step "D05" `
        -Message "Direcciones Windows 192.168.10.x." `
        -Detail (
            ($addresses |
                Select-Object IPAddress, PrefixLength, InterfaceAlias |
                Format-Table -AutoSize |
                Out-String
            ).Trim()
        )

    Write-StepStart -Step "D06" -Purpose "Probar puertos y registrar estado administrado."

    foreach ($target in @(
        @("127.0.0.1", 2222),
        @("127.0.0.1", 8888),
        @("192.168.10.53", 22)
    )) {
        $ok = Test-TcpPort `
            -HostName $target[0] `
            -Port $target[1]

        Write-LabLog `
            -Level $(if ($ok) { "OK" } else { "WARN" }) `
            -Step "D06" `
            -Message "Prueba TCP $($target[0]):$($target[1])." `
            -Detail "Respondió=$ok"
    }

    $knownHostsEntries = @(
        Report-LabKnownHostsEntries `
            -Step "D06-KNOWN-HOSTS"
    )

    $state = Read-LabState -StatePath $statePath

    if ($state) {
        Write-LabLog `
            -Level "INFO" `
            -Step "D06" `
            -Message "Estado administrado." `
            -Detail (($state | ConvertTo-Json -Depth 8 -Compress))
    }
    else {
        Write-StepWarning `
            -Step "D06" `
            -Message "No existe $statePath."
    }

    Write-StepStart `
        -Step "D07" `
        -Purpose "Emitir un resultado explícito de preparación para instalar."

    $blocking = @()
    $informational = @()

    $portOwners = Get-ListeningPortOwners -Ports @(2222, 8888)

    if ($portOwners) {
        $blocking += "Los puertos 2222 o 8888 tienen listeners activos."
    }

    foreach ($name in (Get-RegisteredVmNames -Step "D07-LIST")) {
        if ($name -eq $vmName) {
            continue
        }

        $info = Get-VmInfoMap `
            -Name $name `
            -Step "D07-SCAN"

        $matching = @(
            Get-ForwardingRules -VmInfo $info |
                Where-Object {
                    $_.HostIp -eq "127.0.0.1" -and
                    $_.HostPort -in @("2222", "8888")
                }
        )

        if (-not $matching) {
            continue
        }

        $otherState = [string]$info["VMState"]

        if ($otherState -in @("poweroff", "aborted", "saved")) {
            $informational += (
                "'$name' tiene reglas 2222/8888, pero está $otherState " +
                "y no bloquea los puertos."
            )
        }
        else {
            $blocking += (
                "'$name' está $otherState y tiene reglas 2222/8888."
            )
        }
    }

    foreach ($message in $informational) {
        Write-StepWarning `
            -Step "D07" `
            -Message $message
    }

    if ($knownHostsEntries) {
        $informational += (
            "Hay entradas known_hosts del laboratorio. " +
            "INSTALAR_LAB.cmd las eliminará de forma selectiva antes de iniciar la nueva VM."
        )
    }

    if ($blocking) {
        Write-LabLog `
            -Level "ERROR" `
            -Step "D07" `
            -Message "RESULTADO: NO LISTO PARA INSTALAR." `
            -Detail ($blocking -join " | ")

        throw "El diagnóstico encontró condiciones bloqueantes. Revise D07 en el log."
    }

    Write-LabLog `
        -Level "OK" `
        -Step "D07" `
        -Message "RESULTADO: LISTO PARA INSTALAR." `
        -Detail "No hay listeners activos ni VM activas usando 2222/8888."

    Write-Host ""
    Write-Host "DIAGNÓSTICO COMPLETADO: LISTO PARA INSTALAR" -ForegroundColor Green
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
}
finally {
    Finish-LabOperation `
        -ExitCode $exitCode `
        -Pause
}
