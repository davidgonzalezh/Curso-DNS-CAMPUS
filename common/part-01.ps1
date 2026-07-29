#requires -Version 5.1

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$script:LabContext = $null
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Initialize-LabContext {
    param(
        [Parameter(Mandatory)]
        [string]$Operation
    )

    $scriptRoot = Split-Path -Parent $MyInvocation.PSCommandPath

    if (-not $scriptRoot) {
        $scriptRoot = $PSScriptRoot
    }

    $logRoot = Join-Path $scriptRoot "logs"
    New-Item -ItemType Directory -Force -Path $logRoot | Out-Null

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $safeOperation = $Operation -replace '[^A-Za-z0-9_-]', '_'
    $logPath = Join-Path $logRoot "$safeOperation-$stamp.log"

    $script:LabContext = [ordered]@{
        Operation = $Operation
        ScriptRoot = $scriptRoot
        LogRoot = $logRoot
        LogPath = $logPath
        VBox = $null
        ExitCode = 0
    }

    [System.IO.File]::WriteAllText(
        $logPath,
        "",
        $script:Utf8NoBom
    )

    Write-LabLog `
        -Level "INFO" `
        -Step "INIT" `
        -Message "Inicio de operación: $Operation." `
        -Detail (
            "Usuario=$env:USERDOMAIN\$env:USERNAME; " +
            "PowerShell=$($PSVersionTable.PSVersion); " +
            "PSEdition=$($PSVersionTable.PSEdition); " +
            "Windows=$([Environment]::OSVersion.VersionString); " +
            "ScriptRoot=$scriptRoot"
        )
}

function Write-LabLog {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("DEBUG", "INFO", "OK", "WARN", "ERROR")]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Step,

        [Parameter(Mandatory)]
        [string]$Message,

        [string]$Detail = ""
    )

    if (-not $script:LabContext) {
        throw "Initialize-LabContext debe ejecutarse antes de escribir el log."
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $line = "[$timestamp][$Level][$Step] $Message"

    if ($Detail) {
        $normalized = $Detail -replace "`r?`n", " | "
        $line += " Detalle: $normalized"
    }

    [System.IO.File]::AppendAllText(
        $script:LabContext.LogPath,
        $line + [Environment]::NewLine,
        $script:Utf8NoBom
    )

    $color = switch ($Level) {
        "OK"    { "Green" }
        "WARN"  { "Yellow" }
        "ERROR" { "Red" }
        "DEBUG" { "DarkGray" }
        default { "Cyan" }
    }

    Write-Host "[$Level][$Step] $Message" -ForegroundColor $color

    if ($Detail -and ($Level -in @("WARN", "ERROR"))) {
        Write-Host "    $Detail" -ForegroundColor $color
    }
}

function Write-StepStart {
    param(
        [Parameter(Mandatory)]
        [string]$Step,
        [Parameter(Mandatory)]
        [string]$Purpose
    )

    Write-LabLog `
        -Level "INFO" `
        -Step $Step `
        -Message $Purpose
}

function Write-StepOk {
    param(
        [Parameter(Mandatory)]
        [string]$Step,
        [Parameter(Mandatory)]
        [string]$Message,
        [string]$Detail = ""
    )

    Write-LabLog `
        -Level "OK" `
        -Step $Step `
        -Message $Message `
        -Detail $Detail
}

function Write-StepWarning {
    param(
        [Parameter(Mandatory)]
        [string]$Step,
        [Parameter(Mandatory)]
        [string]$Message,
        [string]$Detail = ""
    )

    Write-LabLog `
        -Level "WARN" `
        -Step $Step `
        -Message $Message `
        -Detail $Detail
}

function Get-VBoxManagePath {
    $candidates = New-Object System.Collections.Generic.List[string]

    if ($env:VBOX_MSI_INSTALL_PATH) {
        $candidates.Add(
            (Join-Path $env:VBOX_MSI_INSTALL_PATH "VBoxManage.exe")
        )
    }

    foreach ($registryPath in @(
        "HKLM:\SOFTWARE\Oracle\VirtualBox",
        "HKLM:\SOFTWARE\WOW6432Node\Oracle\VirtualBox"
    )) {
        try {
            $installDir = (
                Get-ItemProperty `
                    -Path $registryPath `
                    -Name "InstallDir" `
                    -ErrorAction Stop
            ).InstallDir

            if ($installDir) {
                $candidates.Add(
                    (Join-Path $installDir "VBoxManage.exe")
                )
            }
        }
        catch {
        }
    }

    if ($env:ProgramFiles) {
        $candidates.Add(
            (Join-Path $env:ProgramFiles "Oracle\VirtualBox\VBoxManage.exe")
        )
    }

    try {
        $command = Get-Command VBoxManage.exe -ErrorAction Stop
        $candidates.Add($command.Source)
    }
    catch {
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw @"
No se encontró VBoxManage.exe.

Causa probable:
- Oracle VirtualBox no está instalado.
- La instalación está dañada.
- VirtualBox fue instalado en una ruta no registrada.

Acción:
Instale o repare Oracle VirtualBox 7.2.x y repita la operación.
"@
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)

    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Restart-Elevated {
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath,
        [string[]]$AdditionalArguments = @()
    )

    # El proceso elevado normalmente conserva el mismo usuario, pero estas
    # variables garantizan que known_hosts se revise en el perfil que inició
    # el script incluso si UAC solicita otras credenciales administrativas.
    if (-not $env:CURSO_DNS_ORIGINAL_USERPROFILE) {
        $env:CURSO_DNS_ORIGINAL_USERPROFILE = $env:USERPROFILE
    }

    if (-not $env:CURSO_DNS_ORIGINAL_USERNAME) {
        $env:CURSO_DNS_ORIGINAL_USERNAME = $env:USERNAME
    }

    $argumentList = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$ScriptPath`"",
        "-Elevated"
    ) + $AdditionalArguments

    $process = Start-Process `
        -FilePath "powershell.exe" `
        -Verb RunAs `
        -Wait `
        -PassThru `
        -ArgumentList $argumentList

    exit $process.ExitCode
}
