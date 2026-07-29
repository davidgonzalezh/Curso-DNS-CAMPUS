function Invoke-VBox {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [Parameter(Mandatory)]
        [string]$Step,

        [Parameter(Mandatory)]
        [string]$Purpose,

        [switch]$AllowFailure,

        [switch]$LogOutput
    )

    if (-not $script:LabContext.VBox) {
        throw "La ruta de VBoxManage no fue inicializada."
    }

    $commandLine = ConvertTo-WindowsCommandLine -Arguments $Arguments

    Write-LabLog `
        -Level "DEBUG" `
        -Step $Step `
        -Message "Ejecutando VBoxManage para: $Purpose." `
        -Detail "VBoxManage $commandLine"

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $script:LabContext.VBox
    $startInfo.Arguments = $commandLine
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo

    try {
        if (-not $process.Start()) {
            throw "Windows no pudo iniciar VBoxManage.exe."
        }

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        $process.WaitForExit()

        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $exitCode = $process.ExitCode
    }
    finally {
        $process.Dispose()
    }

    $stdout = $stdout.TrimEnd()
    $stderr = $stderr.TrimEnd()

    if ($LogOutput -and ($stdout -or $stderr)) {
        Write-LabLog `
            -Level "DEBUG" `
            -Step $Step `
            -Message "Salida de VBoxManage." `
            -Detail "STDOUT=$stdout; STDERR=$stderr"
    }

    if ($exitCode -ne 0) {
        $explanation = Get-VBoxFailureExplanation `
            -StdOut $stdout `
            -StdErr $stderr `
            -ExitCode $exitCode

        if ($AllowFailure) {
            Write-LabLog `
                -Level "DEBUG" `
                -Step $Step `
                -Message "La consulta terminó con código $exitCode y se considera un resultado permitido." `
                -Detail "Razón=$explanation; STDOUT=$stdout; STDERR=$stderr"

            return [pscustomobject]@{
                ExitCode = $exitCode
                StdOut = $stdout
                StdErr = $stderr
                Explanation = $explanation
            }
        }

        Write-LabLog `
            -Level "ERROR" `
            -Step $Step `
            -Message "Falló VBoxManage: $Purpose." `
            -Detail (
                "ExitCode=$exitCode; Razón=$explanation; " +
                "Comando=VBoxManage $commandLine; " +
                "STDOUT=$stdout; STDERR=$stderr"
            )

        throw @"
Falló la operación de VirtualBox.

Paso: $Step
Objetivo: $Purpose
Código de salida: $exitCode
Explicación: $explanation

Revise el log:
$($script:LabContext.LogPath)
"@
    }

    Write-LabLog `
        -Level "OK" `
        -Step $Step `
        -Message "VBoxManage completó: $Purpose." `
        -Detail "ExitCode=0"

    return [pscustomobject]@{
        ExitCode = 0
        StdOut = $stdout
        StdErr = $stderr
        Explanation = ""
    }
}

function ConvertFrom-VBoxMachineReadable {
    param(
        [string]$Text
    )

    $map = @{}

    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^([^=]+)=(.*)$') {
            $key = $Matches[1].Trim()
            $value = $Matches[2].Trim()

            if ($value.StartsWith('"') -and $value.EndsWith('"')) {
                $value = $value.Substring(1, $value.Length - 2)
                $value = $value.Replace('\"', '"')
                $value = $value.Replace('\\', '\')
            }

            $map[$key] = $value
        }
    }

    return $map
}

function Get-VmInfoMap {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [string]$Step = "VM-INFO",
        [switch]$AllowMissing
    )

    $result = Invoke-VBox `
        -Arguments @(
            "showvminfo",
            $Name,
            "--machinereadable"
        ) `
        -Step $Step `
        -Purpose "consultar la VM '$Name'" `
        -AllowFailure:$AllowMissing

    if ($result.ExitCode -ne 0) {
        return $null
    }

    return ConvertFrom-VBoxMachineReadable -Text $result.StdOut
}

function Get-RegisteredVmNames {
    param(
        [string]$Step = "VM-LIST"
    )

    $result = Invoke-VBox `
        -Arguments @("list", "vms") `
        -Step $Step `
        -Purpose "listar las VM registradas"

    $names = @()

    foreach ($line in ($result.StdOut -split "`r?`n")) {
        if ($line -match '^"(.+)"\s+\{[0-9A-Fa-f-]+\}$') {
            $names += $Matches[1]
        }
    }

    return $names
}

function Get-HostOnlyInterfaces {
    param(
        [string]$Step = "HOSTONLY-LIST"
    )

    $result = Invoke-VBox `
        -Arguments @("list", "hostonlyifs") `
        -Step $Step `
        -Purpose "listar las interfaces Host-Only"

    $interfaces = @()
    $blocks = $result.StdOut -split "(?:`r?`n){2,}"

    foreach ($block in $blocks) {
        $name = [regex]::Match(
            $block,
            "(?m)^Name:\s+(.+)$"
        ).Groups[1].Value.Trim()

        if (-not $name) {
            continue
        }

        $interfaces += [pscustomobject]@{
            Name = $name
            Guid = [regex]::Match(
                $block,
                "(?m)^GUID:\s+(.+)$"
            ).Groups[1].Value.Trim()
            IPAddress = [regex]::Match(
                $block,
                "(?m)^IPAddress:\s+(.+)$"
            ).Groups[1].Value.Trim()
            NetworkMask = [regex]::Match(
                $block,
                "(?m)^NetworkMask:\s+(.+)$"
            ).Groups[1].Value.Trim()
            Status = [regex]::Match(
                $block,
                "(?m)^Status:\s+(.+)$"
            ).Groups[1].Value.Trim()
        }
    }

    return $interfaces
}

function Get-ForwardingRules {
    param(
        [Parameter(Mandatory)]
        [hashtable]$VmInfo
    )

    $rules = @()

    foreach ($key in $VmInfo.Keys) {
        if ($key -match '^Forwarding\(\d+\)$') {
            $parts = $VmInfo[$key] -split ",", 6

            if ($parts.Count -ge 6) {
                $rules += [pscustomobject]@{
                    Key = $key
                    Name = $parts[0]
                    Protocol = $parts[1]
                    HostIp = $parts[2]
                    HostPort = $parts[3]
                    GuestIp = $parts[4]
                    GuestPort = $parts[5]
                }
            }
        }
    }

    return $rules
}
