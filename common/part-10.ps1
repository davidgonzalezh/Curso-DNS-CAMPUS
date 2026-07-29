function Get-SshKeygenPath {
    param(
        [switch]$AllowMissing
    )

    $candidates = New-Object System.Collections.Generic.List[string]

    if ($env:WINDIR) {
        $candidates.Add(
            (Join-Path $env:WINDIR "System32\OpenSSH\ssh-keygen.exe")
        )
    }

    if ($env:ProgramFiles) {
        $candidates.Add(
            (Join-Path $env:ProgramFiles "OpenSSH\ssh-keygen.exe")
        )
    }

    try {
        $command = Get-Command ssh-keygen.exe -ErrorAction Stop
        $candidates.Add($command.Source)
    }
    catch {
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    if ($AllowMissing) {
        return $null
    }

    throw @"
No se encontró ssh-keygen.exe.

La limpieza segura de known_hosts necesita OpenSSH Client porque
ssh-keygen -F y -R también encuentran nombres de host cifrados (hashed).

Instale la característica opcional OpenSSH Client de Windows y repita.
"@
}

function Invoke-SshKeygen {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [Parameter(Mandatory)]
        [string]$Step,

        [Parameter(Mandatory)]
        [string]$Purpose,

        [switch]$AllowNoMatch
    )

    $sshKeygen = Get-SshKeygenPath
    $commandLine = ConvertTo-WindowsCommandLine -Arguments $Arguments

    Write-LabLog `
        -Level "DEBUG" `
        -Step $Step `
        -Message "Ejecutando ssh-keygen para: $Purpose." `
        -Detail "ssh-keygen $commandLine"

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $sshKeygen
    $startInfo.Arguments = $commandLine
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo

    try {
        if (-not $process.Start()) {
            throw "Windows no pudo iniciar ssh-keygen.exe."
        }

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        $process.WaitForExit()

        $stdout = $stdoutTask.GetAwaiter().GetResult().TrimEnd()
        $stderr = $stderrTask.GetAwaiter().GetResult().TrimEnd()
        $exitCode = $process.ExitCode
    }
    finally {
        $process.Dispose()
    }

    if ($exitCode -ne 0) {
        if ($AllowNoMatch -and $exitCode -eq 1 -and -not $stderr) {
            return [pscustomobject]@{
                ExitCode = 1
                StdOut = $stdout
                StdErr = $stderr
            }
        }

        Write-LabLog `
            -Level "ERROR" `
            -Step $Step `
            -Message "Falló ssh-keygen: $Purpose." `
            -Detail (
                "ExitCode=$exitCode; Comando=ssh-keygen $commandLine; " +
                "STDOUT=$stdout; STDERR=$stderr"
            )

        throw @"
ssh-keygen no pudo completar la operación.

Paso: $Step
Objetivo: $Purpose
Código: $exitCode
STDERR: $stderr
"@
    }

    return [pscustomobject]@{
        ExitCode = 0
        StdOut = $stdout
        StdErr = $stderr
    }
}

function Get-LabKnownHostTargets {
    return @(
        "[127.0.0.1]:2222",
        "[localhost]:2222",
        "[::1]:2222",
        "192.168.10.53",
        "[192.168.10.53]:22",
        "resolver1",
        "[resolver1]:22",
        "resolver1.lan.home.arpa",
        "[resolver1.lan.home.arpa]:22",
        "curso-dns-lab",
        "[curso-dns-lab]:22",
        "curso-dns-lab.lan.home.arpa",
        "[curso-dns-lab.lan.home.arpa]:22",
        "curso-dns-lambda",
        "[curso-dns-lambda]:22"
    ) | Select-Object -Unique
}

function Expand-SshKnownHostsPath {
    param(
        [Parameter(Mandatory)]
        [string]$PathText
    )

    $profile = Get-OriginalUserProfile
    $username = if ($env:CURSO_DNS_ORIGINAL_USERNAME) {
        $env:CURSO_DNS_ORIGINAL_USERNAME
    }
    else {
        $env:USERNAME
    }

    $expanded = $PathText.Trim().Trim('"').Trim("'")

    if ($expanded -eq "none") {
        return $null
    }

    $expanded = $expanded.Replace("%d", $profile)
    $expanded = $expanded.Replace("%u", $username)

    if ($expanded.StartsWith("~/") -or $expanded.StartsWith("~\")) {
        $expanded = Join-Path $profile $expanded.Substring(2)
    }

    $expanded = [Environment]::ExpandEnvironmentVariables($expanded)

    try {
        return [System.IO.Path]::GetFullPath($expanded)
    }
    catch {
        return $null
    }
}

function Get-KnownHostsFiles {
    $profile = Get-OriginalUserProfile
    $paths = New-Object System.Collections.Generic.List[string]

    foreach ($path in @(
        (Join-Path $profile ".ssh\known_hosts"),
        (Join-Path $profile ".ssh\known_hosts2"),
        (Join-Path $profile ".ssh\known_hosts.old"),
        (Join-Path $env:ProgramData "ssh\ssh_known_hosts"),
        (Join-Path $env:ProgramData "ssh\ssh_known_hosts.old")
    )) {
        $paths.Add($path)
    }

    $configPath = Join-Path $profile ".ssh\config"

    if (Test-Path -LiteralPath $configPath) {
        foreach ($line in (Get-Content -LiteralPath $configPath -ErrorAction SilentlyContinue)) {
            if ($line -match '^\s*(UserKnownHostsFile|GlobalKnownHostsFile)\s+(.+?)\s*$') {
                $valueText = $Matches[2]

                $tokens = [regex]::Matches(
                    $valueText,
                    '"[^"]+"|''[^'']+''|\S+'
                ) |
                    ForEach-Object {
                        $_.Value
                    }

                foreach ($token in $tokens) {
                    $expanded = Expand-SshKnownHostsPath -PathText $token

                    if ($expanded) {
                        $paths.Add($expanded)
                    }
                }
            }
        }
    }

    return @(
        $paths |
            Where-Object {
                $_
            } |
            Select-Object -Unique
    )
}
