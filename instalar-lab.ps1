#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Elevated
)

. "$PSScriptRoot\curso-dns-common.ps1"

Initialize-LabContext -Operation "instalacion"

$exitCode = 0

try {
    if (-not $Elevated -and -not (Test-IsAdministrator)) {
        Restart-Elevated -ScriptPath $PSCommandPath
    }

    $script:LabContext.VBox = Get-VBoxManagePath

    $vmName = "Curso-DNS-Lambda"
    $ovaName = "Curso_DNS_Lambda_1.1.ova"
    $ovaPath = Join-Path $PSScriptRoot $ovaName
    $hashPath = Join-Path $PSScriptRoot "SHA256SUMS.txt"
    $stateRoot = Join-Path $env:ProgramData "CursoDNSCampus"
    $statePath = Join-Path $stateRoot "lab-state.json"

    $natMac = "080027100101"
    $labMac = "080027100053"

    Write-StepStart `
        -Step "P01" `
        -Purpose "Verificar VirtualBox y registrar la versión instalada."

    $version = Invoke-VBox `
        -Arguments @("--version") `
        -Step "P01" `
        -Purpose "obtener la versión de VirtualBox"

    Write-StepOk `
        -Step "P01" `
        -Message "VirtualBox está disponible." `
        -Detail "VBoxManage=$($script:LabContext.VBox); Version=$($version.StdOut)"

    Write-StepStart `
        -Step "P02" `
        -Purpose "Verificar que la OVA y SHA256SUMS.txt estén completos."

    if (-not (Test-Path -LiteralPath $ovaPath)) {
        throw "No se encontró $ovaName en la misma carpeta del instalador."
    }

    if (-not (Test-Path -LiteralPath $hashPath)) {
        throw "No se encontró SHA256SUMS.txt en la misma carpeta del instalador."
    }

    $hashLine = Get-Content -LiteralPath $hashPath |
        Select-Object -First 1

    $expectedHash = ($hashLine -split "\s+")[0]

    if ($expectedHash -notmatch '^[0-9A-Fa-f]{64}$') {
        throw "SHA256SUMS.txt no contiene un SHA-256 válido de 64 caracteres."
    }

    $actualHash = (
        Get-FileHash `
            -LiteralPath $ovaPath `
            -Algorithm SHA256
    ).Hash

    if ($actualHash -ne $expectedHash) {
        throw @"
El SHA-256 no coincide.

Esperado: $expectedHash
Calculado: $actualHash

La OVA está incompleta, alterada o no corresponde a SHA256SUMS.txt.
"@
    }

    Write-StepOk `
        -Step "P02" `
        -Message "Integridad de la OVA verificada." `
        -Detail "SHA256=$actualHash; Size=$((Get-Item $ovaPath).Length)"

    Write-StepStart `
        -Step "P03" `
        -Purpose "Inspeccionar la OVA sin importarla."

    $dryRun = Invoke-VBox `
        -Arguments @(
            "import",
            $ovaPath,
            "--dry-run"
        ) `
        -Step "P03" `
        -Purpose "validar la estructura de la OVA mediante import --dry-run"

    $dryRunSummary = (
        $dryRun.StdOut -split "`r?`n" |
            Select-Object -First 40
    ) -join " | "

    Write-StepOk `
        -Step "P03" `
        -Message "La OVA es interpretable por VirtualBox." `
        -Detail $dryRunSummary

    Write-StepStart `
        -Step "P04" `
        -Purpose "Comprobar instalaciones previas y conflictos antes de modificar Windows."

    $state = Read-LabState -StatePath $statePath
    $vmInfo = Get-VmInfoMap `
        -Name $vmName `
        -Step "P04-VM" `
        -AllowMissing

    if ($vmInfo -and -not $state) {
        Write-StepWarning `
            -Step "P04-PARTIAL" `
            -Message "Existe una VM parcial sin estado administrado." `
            -Detail (
                "VM=$vmName; VMState=$($vmInfo["VMState"]); " +
                "Puede provenir de una instalación interrumpida."
            )

        $choice = Read-LabChoice `
            -Prompt "¿Eliminar la VM parcial y continuar con una importación limpia?" `
            -Allowed @("E", "C") `
            -Default "E"

        if ($choice -eq "C") {
            throw "El usuario decidió conservar la VM parcial '$vmName'."
        }

        Ensure-VmStoppedInteractive `
            -Name $vmName `
            -Step "P04-PARTIAL-STOP" `
            -Reason "La VM parcial debe detenerse antes de eliminarla."

        Invoke-VBox `
            -Arguments @(
                "unregistervm",
                $vmName,
                "--delete"
            ) `
            -Step "P04-PARTIAL-DELETE" `
            -Purpose "eliminar la importación parcial antes de reinstalar" |
            Out-Null

        $vmInfo = $null

        Write-StepOk `
            -Step "P04-PARTIAL" `
            -Message "Importación parcial eliminada; se continuará desde cero."
    }

    $allowedInterfaceName = ""

    if ($state -and $state.HostOnlyInterfaceName) {
        $allowedInterfaceName = [string]$state.HostOnlyInterfaceName
    }

    Resolve-LabNetworkConflictInteractive `
        -Step "P04-NETWORK" `
        -AllowedInterfaceName $allowedInterfaceName

    if ($vmInfo -and $state) {
        $managedState = [string]$vmInfo["VMState"]

        if ($managedState -notin @("poweroff", "aborted")) {
            Ensure-VmStoppedInteractive `
                -Name $vmName `
                -Step "P04-MANAGED-STOP" `
                -Reason (
                    "La instalación administrada debe detenerse antes de " +
                    "reparar o volver a validar sus redes."
                )

            $vmInfo = Get-VmInfoMap `
                -Name $vmName `
                -Step "P04-MANAGED-REFRESH"
        }
    }

    $activeVmConflicts = @()
    $stoppedVmRules = @()

    foreach ($otherVmName in (Get-RegisteredVmNames -Step "P04-LIST")) {
        if ($otherVmName -eq $vmName) {
            continue
        }

        $otherInfo = Get-VmInfoMap `
            -Name $otherVmName `
            -Step "P04-SCAN"

        $otherState = $otherInfo["VMState"]

        foreach ($rule in (Get-ForwardingRules -VmInfo $otherInfo)) {
            if ($rule.HostIp -eq "127.0.0.1" -and
                $rule.HostPort -in @("2222", "8888")) {

                $record = [pscustomobject]@{
                    Vm = $otherVmName
                    Rule = $rule.Name
                    Host = "$($rule.HostIp):$($rule.HostPort)"
                    GuestPort = $rule.GuestPort
                    State = $otherState
                }

                if ($otherState -in @("poweroff", "aborted", "saved")) {
                    $stoppedVmRules += $record
                }
                else {
                    $activeVmConflicts += $record
                }
            }
        }
    }

    if ($stoppedVmRules) {
        Write-StepWarning `
            -Step "P04" `
            -Message "Existen reglas iguales en VM detenidas; no bloquean los puertos del host." `
            -Detail (
                (
                    $stoppedVmRules |
                        Format-Table -AutoSize |
                        Out-String
                ).Trim()
            )
    }

    if ($activeVmConflicts) {
        $detail = (
            $activeVmConflicts |
                Format-Table -AutoSize |
                Out-String
        ).Trim()

        Write-StepWarning `
            -Step "P04-ACTIVE-VM" `
            -Message "Otra VM activa usa los puertos del laboratorio." `
            -Detail $detail

        foreach ($conflictingVm in (
            $activeVmConflicts |
                Select-Object -ExpandProperty Vm -Unique
        )) {
            Ensure-VmStoppedInteractive `
                -Name $conflictingVm `
                -Step "P04-STOP-$conflictingVm" `
                -Reason "La VM activa ocupa o puede ocupar 127.0.0.1:2222/8888."
        }
    }

    Resolve-ListeningPortConflictsInteractive `
        -Ports @(2222, 8888) `
        -Step "P04-PORTS"

    Remove-LabKnownHostsEntries `
        -Step "P04-KNOWN-HOSTS"

    Write-StepOk `
        -Step "P04" `
        -Message "Conflictos corregibles resueltos; el entorno está listo para instalar."

    if (-not $state) {
        $state = [ordered]@{
            SchemaVersion = 3
            Product = "Curso DNS CAMPUS"
            Version = "1.1"
            Stage = "Started"
            VmName = $vmName
            VmUuid = ""
            HostOnlyInterfaceName = ""
            HostOnlyInterfaceGuid = ""
            HostOnlyCreatedByInstaller = $false
            NatRules = @("ssh", "webssh")
            RoutesCreatedByInstaller = $false
            FirewallRulesCreatedByInstaller = $false
            StartedAtUtc = [DateTime]::UtcNow.ToString("o")
        }

        Save-LabState `
            -State $state `
            -StatePath $statePath
    }

    Write-StepStart `
        -Step "P05" `
        -Purpose "Crear la interfaz Host-Only exclusiva del laboratorio."

    $interfaces = @(Get-HostOnlyInterfaces -Step "P05-LIST")
    $hostOnly = $null

    if ($state.HostOnlyInterfaceGuid) {
        $hostOnly = $interfaces |
            Where-Object {
                $_.Guid -eq $state.HostOnlyInterfaceGuid
            } |
            Select-Object -First 1
    }

    if (-not $hostOnly -and $state.HostOnlyInterfaceName) {
        $hostOnly = $interfaces |
            Where-Object {
                $_.Name -eq $state.HostOnlyInterfaceName
            } |
            Select-Object -First 1
    }

    if (-not $hostOnly) {
        $beforeGuids = @(
            $interfaces |
                Select-Object -ExpandProperty Guid
        )

        Invoke-VBox `
            -Arguments @(
                "hostonlyif",
                "create"
            ) `
            -Step "P05-CREATE" `
            -Purpose "crear una interfaz Host-Only en Windows" |
            Out-Null

        $interfacesAfter = @(
            Get-HostOnlyInterfaces -Step "P05-AFTER"
        )

        $hostOnly = $interfacesAfter |
            Where-Object {
                $_.Guid -notin $beforeGuids
            } |
            Select-Object -First 1

        if (-not $hostOnly) {
            throw "VirtualBox informó éxito, pero no fue posible identificar la interfaz Host-Only recién creada."
        }

        $state.HostOnlyCreatedByInstaller = $true
        $state.HostOnlyInterfaceName = $hostOnly.Name
        $state.HostOnlyInterfaceGuid = $hostOnly.Guid
        $state.Stage = "HostOnlyCreated"

        Save-LabState `
            -State $state `
            -StatePath $statePath
    }

    Invoke-VBox `
        -Arguments @(
            "hostonlyif",
            "ipconfig",
            $hostOnly.Name,
            "--ip=192.168.10.1",
            "--netmask=255.255.255.0"
        ) `
        -Step "P05-IP" `
        -Purpose "asignar 192.168.10.1/24 a la interfaz Host-Only" |
        Out-Null

    Invoke-VBox `
        -Arguments @(
            "dhcpserver",
            "remove",
            "--interface=$($hostOnly.Name)"
        ) `
        -Step "P05-DHCP" `
        -Purpose "retirar un DHCP asociado a la interfaz Host-Only, si existe" `
        -AllowFailure |
        Out-Null

    $hostOnly = @(
        Get-HostOnlyInterfaces -Step "P05-VERIFY"
    ) |
        Where-Object {
            $_.Guid -eq $state.HostOnlyInterfaceGuid
        } |
        Select-Object -First 1

    if (-not $hostOnly -or
        $hostOnly.IPAddress -ne "192.168.10.1" -or
        $hostOnly.NetworkMask -ne "255.255.255.0") {

        throw "La interfaz Host-Only no quedó configurada como 192.168.10.1/24."
    }

    Write-StepOk `
        -Step "P05" `
        -Message "Interfaz Host-Only preparada." `
        -Detail "Name=$($hostOnly.Name); GUID=$($hostOnly.Guid); IP=192.168.10.1/24"

    Write-StepStart `
        -Step "P06" `
        -Purpose "Importar la appliance cuando la VM todavía no existe."

    if (-not $vmInfo) {
        Invoke-VBox `
            -Arguments @(
                "import",
                $ovaPath,
                "--vsys=0",
                "--vmname=$vmName"
            ) `
            -Step "P06-IMPORT" `
            -Purpose "importar $ovaName como '$vmName'" `
            -LogOutput |
            Out-Null

        $vmInfo = Get-VmInfoMap `
            -Name $vmName `
            -Step "P06-VERIFY"
    }

    $state.VmUuid = $vmInfo["UUID"]
    $state.Stage = "VmImported"

    Save-LabState `
        -State $state `
        -StatePath $statePath

    foreach ($entry in @(
        @("CursoDNSCampus/Managed", "true"),
        @("CursoDNSCampus/Version", "1.1"),
        @("CursoDNSCampus/HostOnlyInterfaceName", $hostOnly.Name),
        @("CursoDNSCampus/HostOnlyInterfaceGuid", $hostOnly.Guid)
    )) {
        Invoke-VBox `
            -Arguments @(
                "setextradata",
                $vmName,
                $entry[0],
                $entry[1]
            ) `
            -Step "P06-META" `
            -Purpose "registrar metadato $($entry[0])" |
            Out-Null
    }

    Write-StepOk `
        -Step "P06" `
        -Message "VM importada y registrada." `
        -Detail "Name=$vmName; UUID=$($state.VmUuid)"

    Write-StepStart `
        -Step "P07" `
        -Purpose "Normalizar el estado de la VM y configurar sus dos adaptadores."

    $vmInfo = Get-VmInfoMap `
        -Name $vmName `
        -Step "P07-STATE"

    Ensure-VmStoppedInteractive `
        -Name $vmName `
        -Step "P07-STOP" `
        -Reason "La VM debe estar detenida para configurar adaptadores y port forwardings."

    $vmInfo = Get-VmInfoMap `
        -Name $vmName `
        -Step "P07-STATE-AFTER-STOP"

    $vmState = [string]$vmInfo["VMState"]

    Invoke-VBox `
        -Arguments @(
            "modifyvm",
            $vmName,
            "--nic1=nat",
            "--nic-type1=82540EM",
            "--mac-address1=$natMac",
            "--cable-connected1=on"
        ) `
        -Step "P07-NAT" `
        -Purpose "configurar Adaptador 1 como NAT" |
        Out-Null

    # La OVA ya puede contener estas reglas. No se borran y recrean
    # innecesariamente: se verifican y solamente se corrigen si difieren.
    Ensure-NatRule `
        -VmName $vmName `
        -RuleName "ssh" `
        -Protocol "tcp" `
        -HostIp "127.0.0.1" `
        -HostPort 2222 `
        -GuestIp "" `
        -GuestPort 22 `
        -Step "P07-SSH"

    Ensure-NatRule `
        -VmName $vmName `
        -RuleName "webssh" `
        -Protocol "tcp" `
        -HostIp "127.0.0.1" `
        -HostPort 8888 `
        -GuestIp "" `
        -GuestPort 8888 `
        -Step "P07-WEBSSH"

    Invoke-VBox `
        -Arguments @(
            "modifyvm",
            $vmName,
            "--nic2=hostonly",
            "--nic-type2=82540EM",
            "--mac-address2=$labMac",
            "--host-only-adapter2=$($hostOnly.Name)",
            "--cable-connected2=on"
        ) `
        -Step "P07-HOSTONLY" `
        -Purpose "conectar Adaptador 2 a la interfaz Host-Only" |
        Out-Null

    $vmInfo = Get-VmInfoMap `
        -Name $vmName `
        -Step "P07-VERIFY"

    $rules = @(Get-ForwardingRules -VmInfo $vmInfo)

    $sshRule = $rules |
        Where-Object {
            $_.Name -eq "ssh" -and
            $_.HostIp -eq "127.0.0.1" -and
            $_.HostPort -eq "2222" -and
            $_.GuestPort -eq "22"
        }

    $webRule = $rules |
        Where-Object {
            $_.Name -eq "webssh" -and
            $_.HostIp -eq "127.0.0.1" -and
            $_.HostPort -eq "8888" -and
            $_.GuestPort -eq "8888"
        }

    if ($vmInfo["nic1"] -ne "nat" -or
        $vmInfo["nic2"] -ne "hostonly" -or
        $vmInfo["hostonlyadapter2"] -ne $hostOnly.Name -or
        -not $sshRule -or
        -not $webRule) {

        throw @"
La verificación posterior no coincide con la arquitectura requerida.

nic1=$($vmInfo["nic1"])
nic2=$($vmInfo["nic2"])
hostonlyadapter2=$($vmInfo["hostonlyadapter2"])
sshRule=$([bool]$sshRule)
websshRule=$([bool]$webRule)
"@
    }

    $state.Stage = "VmConfigured"

    Save-LabState `
        -State $state `
        -StatePath $statePath

    Write-StepOk `
        -Step "P07" `
        -Message "Red y port forwardings verificados." `
        -Detail (
            "nic1=nat; 127.0.0.1:2222->22; " +
            "127.0.0.1:8888->8888; nic2=hostonly; " +
            "HostOnly=$($hostOnly.Name)"
        )

    Write-StepStart `
        -Step "P08" `
        -Purpose "Iniciar la VM en modo Headless."

    $startResult = Invoke-VBox `
        -Arguments @(
            "startvm",
            $vmName,
            "--type=headless"
        ) `
        -Step "P08-START" `
        -Purpose "iniciar '$vmName' en modo Headless" `
        -AllowFailure

    if ($startResult.ExitCode -ne 0) {
        $failedInfo = Get-VmInfoMap `
            -Name $vmName `
            -Step "P08-FAIL-INFO" `
            -AllowMissing

        $vboxLog = Get-VMLogTail `
            -VmInfo $failedInfo `
            -Lines 100

        Write-LabLog `
            -Level "ERROR" `
            -Step "P08" `
            -Message "VirtualBox no pudo iniciar la VM." `
            -Detail "Razón=$($startResult.Explanation); VBoxLogTail=$vboxLog"

        throw "La VM fue creada y configurada, pero no pudo iniciar. El log incluye el final de VBox.log."
    }

    $state.Stage = "VmStarted"

    Save-LabState `
        -State $state `
        -StatePath $statePath

    Write-StepOk `
        -Step "P08" `
        -Message "Orden de arranque aceptada por VirtualBox."

    Write-StepStart `
        -Step "P09" `
        -Purpose "Comprobar SSH, WebSSH y acceso directo a 192.168.10.53."

    $sshNatOk = Wait-TcpPort `
        -HostName "127.0.0.1" `
        -Port 2222 `
        -TimeoutSeconds 180

    if (-not $sshNatOk) {
        throw @"
La VM arrancó, pero 127.0.0.1:2222 no respondió en 180 segundos.

Posibles causas:
- Ubuntu no completó el arranque;
- OpenSSH no está activo;
- la OVA no contiene la configuración esperada;
- la VM abortó después de iniciar.
"@
    }

    Write-StepOk `
        -Step "P09-SSH-NAT" `
        -Message "SSH por NAT responde en 127.0.0.1:2222."

    $webSshOk = Wait-TcpPort `
        -HostName "127.0.0.1" `
        -Port 8888 `
        -TimeoutSeconds 180

    if (-not $webSshOk) {
        throw @"
SSH responde, pero WebSSH no responde en 127.0.0.1:8888.

La red NAT funciona. El fallo está dentro de Ubuntu:
- webssh.service no está activo;
- WebSSH no escucha en TCP/8888;
- el servicio falló al iniciar.
"@
    }

    Write-StepOk `
        -Step "P09-WEBSSH" `
        -Message "WebSSH responde en 127.0.0.1:8888."

    $sshLabOk = Wait-TcpPort `
        -HostName "192.168.10.53" `
        -Port 22 `
        -TimeoutSeconds 120

    if (-not $sshLabOk) {
        throw @"
NAT y WebSSH funcionan, pero 192.168.10.53:22 no responde.

La causa está en la segunda interfaz:
- Netplan no asignó 192.168.10.53;
- la MAC de lab0 no coincide;
- Adaptador 2 no fue reconocido por Ubuntu.
"@
    }

    Write-StepOk `
        -Step "P09-HOSTONLY" `
        -Message "SSH directo responde en 192.168.10.53:22."

    $state.Stage = "Installed"
    $state.CompletedAtUtc = [DateTime]::UtcNow.ToString("o")

    Save-LabState `
        -State $state `
        -StatePath $statePath

    Start-Process "http://127.0.0.1:8888/"

    Write-Host ""
    Write-Host "INSTALACIÓN COMPLETADA" -ForegroundColor Green
    Write-Host "WebSSH:  http://127.0.0.1:8888/"
    Write-Host "SSH NAT: ssh -p 2222 vagrant@127.0.0.1"
    Write-Host "SSH LAB: ssh vagrant@192.168.10.53"
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
    Write-Host "ERROR DE INSTALACIÓN" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "No se cerrará esta ventana hasta que presione Enter." -ForegroundColor Yellow
}
finally {
    Finish-LabOperation `
        -ExitCode $exitCode `
        -Pause
}
