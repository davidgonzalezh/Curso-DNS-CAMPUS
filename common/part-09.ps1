function Resolve-LabNetworkConflictInteractive {
    param(
        [Parameter(Mandatory)]
        [string]$Step,

        [string]$AllowedInterfaceName = ""
    )

    $conflicts = @(
        Get-NetIPAddress `
            -AddressFamily IPv4 `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $_.IPAddress -like "192.168.10.*" -and
                $_.InterfaceAlias -ne $AllowedInterfaceName
            }
    )

    if (-not $conflicts) {
        Write-StepOk `
            -Step $Step `
            -Message "La red 192.168.10.0/24 está disponible."

        return
    }

    $hostOnlyInterfaces = @(
        Get-HostOnlyInterfaces -Step "$Step-HOSTONLY"
    )

    $safeCandidates = @()
    $unsafeConflicts = @()

    foreach ($conflict in $conflicts) {
        $hostOnly = $hostOnlyInterfaces |
            Where-Object {
                $_.Name -eq $conflict.InterfaceAlias -and
                $_.IPAddress -eq "192.168.10.1" -and
                $_.NetworkMask -eq "255.255.255.0"
            } |
            Select-Object -First 1

        if ($hostOnly) {
            $safeCandidates += $hostOnly
        }
        else {
            $unsafeConflicts += $conflict
        }
    }

    if ($unsafeConflicts) {
        $detail = (
            $unsafeConflicts |
                Select-Object IPAddress, PrefixLength, InterfaceAlias, InterfaceIndex |
                Format-Table -AutoSize |
                Out-String
        ).Trim()

        throw @"
La red 192.168.10.0/24 está en uso por una interfaz que no puede
eliminarse de forma segura como parte del laboratorio.

$detail

Puede pertenecer a una LAN física, VPN u otra plataforma.
Cambie esa red o ejecute el laboratorio en otro host.
"@
    }

    foreach ($interface in ($safeCandidates | Sort-Object Guid -Unique)) {
        $users = @()

        foreach ($vmName in (Get-RegisteredVmNames -Step "$Step-VMS")) {
            $info = Get-VmInfoMap `
                -Name $vmName `
                -Step "$Step-SCAN"

            $indexes = @()

            foreach ($key in $info.Keys) {
                if ($key -match '^hostonlyadapter(\d+)$' -and
                    $info[$key] -eq $interface.Name) {

                    $indexes += [int]$Matches[1]
                }
            }

            if ($indexes) {
                $users += [pscustomobject]@{
                    Vm = $vmName
                    State = [string]$info["VMState"]
                    AdapterIndexes = @($indexes)
                }
            }
        }

        $detail = (
            "Interface=$($interface.Name); GUID=$($interface.Guid); " +
            "Users=$(
                (
                    $users |
                        ForEach-Object {
                            "$($_.Vm)[$($_.State)]/NIC=$($_.AdapterIndexes -join ',')"
                        }
                ) -join '; '
            )"
        )

        Write-StepWarning `
            -Step $Step `
            -Message "Se encontró una interfaz Host-Only anterior del laboratorio." `
            -Detail $detail

        $choice = Read-LabChoice `
            -Prompt "¿Desconectar esta red antigua, eliminarla y continuar?" `
            -Allowed @("L", "C") `
            -Default "L"

        if ($choice -eq "C") {
            throw "El usuario decidió conservar la interfaz '$($interface.Name)'."
        }

        foreach ($user in $users) {
            Ensure-VmStoppedInteractive `
                -Name $user.Vm `
                -Step "$Step-STOP-$($user.Vm)" `
                -Reason (
                    "La VM usa la interfaz Host-Only anterior " +
                    "'$($interface.Name)', que debe retirarse."
                )

            foreach ($index in $user.AdapterIndexes) {
                Invoke-VBox `
                    -Arguments @(
                        "modifyvm",
                        $user.Vm,
                        "--nic$index=none"
                    ) `
                    -Step "$Step-DISCONNECT" `
                    -Purpose (
                        "desconectar Adaptador $index de '$($user.Vm)' " +
                        "de la interfaz Host-Only anterior"
                    ) |
                    Out-Null
            }
        }

        Invoke-VBox `
            -Arguments @(
                "dhcpserver",
                "remove",
                "--interface=$($interface.Name)"
            ) `
            -Step "$Step-DHCP" `
            -Purpose "eliminar DHCP asociado a la interfaz anterior, si existe" `
            -AllowFailure |
            Out-Null

        Invoke-VBox `
            -Arguments @(
                "hostonlyif",
                "remove",
                $interface.Name
            ) `
            -Step "$Step-REMOVE" `
            -Purpose "eliminar la interfaz Host-Only anterior" |
            Out-Null

        $remaining = @(
            Get-HostOnlyInterfaces -Step "$Step-VERIFY"
        ) |
            Where-Object {
                $_.Guid -eq $interface.Guid
            }

        if ($remaining) {
            throw "La interfaz '$($interface.Name)' continúa registrada después de eliminarla."
        }

        Write-StepOk `
            -Step $Step `
            -Message "Interfaz Host-Only anterior retirada y verificada." `
            -Detail "Name=$($interface.Name); GUID=$($interface.Guid)"
    }

    $remainingConflicts = @(
        Get-NetIPAddress `
            -AddressFamily IPv4 `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $_.IPAddress -like "192.168.10.*" -and
                $_.InterfaceAlias -ne $AllowedInterfaceName
            }
    )

    if ($remainingConflicts) {
        throw "La red 192.168.10.0/24 sigue ocupada después de la corrección interactiva."
    }
}

function Get-OriginalUserProfile {
    if ($env:CURSO_DNS_ORIGINAL_USERPROFILE -and
        (Test-Path -LiteralPath $env:CURSO_DNS_ORIGINAL_USERPROFILE)) {

        return $env:CURSO_DNS_ORIGINAL_USERPROFILE
    }

    return $env:USERPROFILE
}
