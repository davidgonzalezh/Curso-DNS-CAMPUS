function Save-LabState {
    param(
        [Parameter(Mandatory)]
        [hashtable]$State,
        [Parameter(Mandatory)]
        [string]$StatePath
    )

    $stateRoot = Split-Path -Parent $StatePath
    New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null

    $temporaryPath = "$StatePath.tmp"

    $json = $State | ConvertTo-Json -Depth 8

    [System.IO.File]::WriteAllText(
        $temporaryPath,
        $json,
        $script:Utf8NoBom
    )

    Move-Item `
        -LiteralPath $temporaryPath `
        -Destination $StatePath `
        -Force

    Write-LabLog `
        -Level "DEBUG" `
        -Step "STATE" `
        -Message "Estado de instalación actualizado." `
        -Detail "Path=$StatePath; Stage=$($State.Stage)"
}

function Read-LabState {
    param(
        [Parameter(Mandatory)]
        [string]$StatePath
    )

    if (-not (Test-Path -LiteralPath $StatePath)) {
        return $null
    }

    try {
        return (
            Get-Content `
                -LiteralPath $StatePath `
                -Raw `
                -ErrorAction Stop
        ) | ConvertFrom-Json
    }
    catch {
        throw "El archivo de estado está dañado: $StatePath"
    }
}

function Read-LabChoice {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [Parameter(Mandatory)]
        [string[]]$Allowed,

        [string]$Default = ""
    )

    $normalizedAllowed = @(
        $Allowed |
            ForEach-Object {
                $_.ToUpperInvariant()
            }
    )

    do {
        $suffix = if ($Default) {
            " [Opciones: $($Allowed -join '/'); predeterminado: $Default]"
        }
        else {
            " [Opciones: $($Allowed -join '/')]"
        }

        $answer = (Read-Host "$Prompt$suffix").Trim().ToUpperInvariant()

        if (-not $answer -and $Default) {
            $answer = $Default.ToUpperInvariant()
        }

        if ($answer -notin $normalizedAllowed) {
            Write-Host "Opción no válida." -ForegroundColor Yellow
        }
    }
    while ($answer -notin $normalizedAllowed)

    return $answer
}
