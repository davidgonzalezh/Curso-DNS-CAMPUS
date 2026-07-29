function Ensure-NatRule {
    param(
        [Parameter(Mandatory)]
        [string]$VmName,

        [Parameter(Mandatory)]
        [string]$RuleName,

        [Parameter(Mandatory)]
        [ValidateSet("tcp", "udp")]
        [string]$Protocol,

        [Parameter(Mandatory)]
        [string]$HostIp,

        [Parameter(Mandatory)]
        [int]$HostPort,

        [string]$GuestIp = "",

        [Parameter(Mandatory)]
        [int]$GuestPort,

        [Parameter(Mandatory)]
        [string]$Step
    )

    $vmInfo = Get-VmInfoMap `
        -Name $VmName `
        -Step "$Step-CHECK"

    $rules = @(Get-ForwardingRules -VmInfo $vmInfo)

    $exact = @(
        $rules |
            Where-Object {
                $_.Name -eq $RuleName -and
                $_.Protocol -eq $Protocol -and
                $_.HostIp -eq $HostIp -and
                $_.HostPort -eq [string]$HostPort -and
                $_.GuestIp -eq $GuestIp -and
                $_.GuestPort -eq [string]$GuestPort
            }
    )

    if ($exact) {
        Write-StepOk `
            -Step $Step `
            -Message "La regla NAT '$RuleName' ya es correcta; se conserva sin recrearla." `
            -Detail "$HostIp`:$HostPort -> $GuestIp`:$GuestPort/$Protocol"

        return
    }

    $sameName = @(
        $rules |
            Where-Object {
                $_.Name -eq $RuleName
            }
    )

    if ($sameName) {
        Remove-NatRuleVerified `
            -VmName $VmName `
            -RuleName $RuleName `
            -Step "$Step-REMOVE-NAME"
    }

    $vmInfo = Get-VmInfoMap `
        -Name $VmName `
        -Step "$Step-RESCAN"

    $bindingConflicts = @(
        Get-ForwardingRules -VmInfo $vmInfo |
            Where-Object {
                $_.Protocol -eq $Protocol -and
                $_.HostIp -eq $HostIp -and
                $_.HostPort -eq [string]$HostPort
            }
    )

    foreach ($conflict in $bindingConflicts) {
        Remove-NatRuleVerified `
            -VmName $VmName `
            -RuleName $conflict.Name `
            -Step "$Step-REMOVE-BINDING"
    }

    $ruleSpec = (
        "$RuleName,$Protocol,$HostIp,$HostPort,$GuestIp,$GuestPort"
    )

    $attempts = @(
        [pscustomobject]@{
            Label = "Oracle-7.2"
            Arguments = @(
                "modifyvm",
                $VmName,
                "--nat-pf1",
                $ruleSpec
            )
        },
        [pscustomobject]@{
            Label = "Legacy"
            Arguments = @(
                "modifyvm",
                $VmName,
                "--natpf1",
                $ruleSpec
            )
        },
        [pscustomobject]@{
            Label = "Equals-fallback"
            Arguments = @(
                "modifyvm",
                $VmName,
                "--nat-pf1=$ruleSpec"
            )
        }
    )

    $failures = @()

    foreach ($attempt in $attempts) {
        $result = Invoke-VBox `
            -Arguments ([string[]]$attempt.Arguments) `
            -Step "$Step-ADD-$($attempt.Label)" `
            -Purpose "crear la regla NAT '$RuleName' usando $($attempt.Label)" `
            -AllowFailure

        $vmInfo = Get-VmInfoMap `
            -Name $VmName `
            -Step "$Step-VERIFY"

        $verified = @(
            Get-ForwardingRules -VmInfo $vmInfo |
                Where-Object {
                    $_.Name -eq $RuleName -and
                    $_.Protocol -eq $Protocol -and
                    $_.HostIp -eq $HostIp -and
                    $_.HostPort -eq [string]$HostPort -and
                    $_.GuestIp -eq $GuestIp -and
                    $_.GuestPort -eq [string]$GuestPort
                }
        )

        if ($verified) {
            Write-StepOk `
                -Step $Step `
                -Message "Regla NAT '$RuleName' creada y verificada." `
                -Detail (
                    "Sintaxis=$($attempt.Label); " +
                    "$HostIp`:$HostPort -> $GuestIp`:$GuestPort/$Protocol"
                )

            return
        }

        $failures += (
            "$($attempt.Label): ExitCode=$($result.ExitCode); " +
            "Explanation=$($result.Explanation)"
        )
    }

    throw @"
No fue posible crear y verificar la regla NAT '$RuleName'.

Intentos:
$($failures -join [Environment]::NewLine)
"@
}

function Test-TcpPort {
    param(
        [Parameter(Mandatory)]
        [string]$HostName,
        [Parameter(Mandatory)]
        [int]$Port,
        [int]$TimeoutMs = 2000
    )

    $client = New-Object System.Net.Sockets.TcpClient

    try {
        $async = $client.BeginConnect($HostName, $Port, $null, $null)

        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            return $false
        }

        $client.EndConnect($async)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $client.Close()
    }
}

function Wait-TcpPort {
    param(
        [Parameter(Mandatory)]
        [string]$HostName,
        [Parameter(Mandatory)]
        [int]$Port,
        [int]$TimeoutSeconds = 180,
        [int]$IntervalSeconds = 3
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    do {
        if (Test-TcpPort -HostName $HostName -Port $Port) {
            return $true
        }

        Start-Sleep -Seconds $IntervalSeconds
    }
    while ((Get-Date) -lt $deadline)

    return $false
}

function Get-ListeningPortOwners {
    param(
        [int[]]$Ports
    )

    $results = @()

    foreach ($port in $Ports) {
        $connections = Get-NetTCPConnection `
            -State Listen `
            -LocalPort $port `
            -ErrorAction SilentlyContinue

        foreach ($connection in $connections) {
            $processName = ""

            try {
                $processName = (
                    Get-Process `
                        -Id $connection.OwningProcess `
                        -ErrorAction Stop
                ).ProcessName
            }
            catch {
                $processName = "desconocido"
            }

            $results += [pscustomobject]@{
                Port = $port
                Address = $connection.LocalAddress
                ProcessId = $connection.OwningProcess
                ProcessName = $processName
            }
        }
    }

    return $results
}

function Get-VMLogTail {
    param(
        [hashtable]$VmInfo,
        [int]$Lines = 80
    )

    if (-not $VmInfo -or -not $VmInfo.ContainsKey("LogFldr")) {
        return ""
    }

    $logPath = Join-Path $VmInfo["LogFldr"] "VBox.log"

    if (-not (Test-Path -LiteralPath $logPath)) {
        return ""
    }

    return (
        Get-Content `
            -LiteralPath $logPath `
            -Tail $Lines `
            -ErrorAction SilentlyContinue
    ) -join [Environment]::NewLine
}
