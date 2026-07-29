function Find-LabKnownHostsEntries {
    param(
        [Parameter(Mandatory)]
        [string]$Step
    )

    $results = @()
    $sshKeygen = Get-SshKeygenPath -AllowMissing
    $files = @(
        Get-KnownHostsFiles |
            Where-Object {
                Test-Path -LiteralPath $_
            }
    )

    if (-not $files) {
        return @()
    }

    if (-not $sshKeygen) {
        throw "Existen archivos known_hosts, pero no está disponible ssh-keygen.exe para analizarlos de forma segura."
    }

    foreach ($file in $files) {
        foreach ($target in (Get-LabKnownHostTargets)) {
            $find = Invoke-SshKeygen `
                -Arguments @(
                    "-F",
                    $target,
                    "-f",
                    $file
                ) `
                -Step "$Step-FIND" `
                -Purpose "buscar '$target' únicamente dentro de '$file'" `
                -AllowNoMatch

            if ($find.ExitCode -eq 0 -and $find.StdOut) {
                $matchedLines = @(
                    $find.StdOut -split "`r?`n" |
                        Where-Object {
                            $_ -and -not $_.StartsWith("#")
                        }
                )

                $results += [pscustomobject]@{
                    File = $file
                    Target = $target
                    MatchCount = $matchedLines.Count
                }
            }
        }
    }

    return $results
}

function Remove-LabKnownHostsEntries {
    param(
        [Parameter(Mandatory)]
        [string]$Step
    )

    Write-StepStart `
        -Step $Step `
        -Purpose "Buscar y eliminar exclusivamente claves SSH relacionadas con el laboratorio."

    $entries = @(
        Find-LabKnownHostsEntries -Step $Step
    )

    if (-not $entries) {
        Write-StepOk `
            -Step $Step `
            -Message "No existen entradas known_hosts relacionadas con el laboratorio."

        return
    }

    foreach ($entry in (
        $entries |
            Sort-Object File, Target -Unique
    )) {
        Write-LabLog `
            -Level "INFO" `
            -Step $Step `
            -Message "Entrada del laboratorio encontrada." `
            -Detail (
                "File=$($entry.File); Target=$($entry.Target); " +
                "Matches=$($entry.MatchCount)"
            )

        Invoke-SshKeygen `
            -Arguments @(
                "-R",
                $entry.Target,
                "-f",
                $entry.File
            ) `
            -Step "$Step-REMOVE" `
            -Purpose "eliminar '$($entry.Target)' de '$($entry.File)'" |
            Out-Null

        $verify = Invoke-SshKeygen `
            -Arguments @(
                "-F",
                $entry.Target,
                "-f",
                $entry.File
            ) `
            -Step "$Step-VERIFY" `
            -Purpose "verificar que '$($entry.Target)' ya no exista" `
            -AllowNoMatch

        if ($verify.ExitCode -eq 0 -and $verify.StdOut) {
            throw "La entrada '$($entry.Target)' continúa presente en '$($entry.File)'."
        }

        Write-StepOk `
            -Step $Step `
            -Message "Entrada SSH del laboratorio eliminada y verificada." `
            -Detail "File=$($entry.File); Target=$($entry.Target)"
    }

    $remaining = @(
        Find-LabKnownHostsEntries -Step "$Step-FINAL"
    )

    if ($remaining) {
        throw "La verificación final todavía detecta entradas known_hosts del laboratorio."
    }

    Write-StepOk `
        -Step $Step `
        -Message "known_hosts quedó libre de entradas del laboratorio; las demás entradas se conservaron."
}

function Report-LabKnownHostsEntries {
    param(
        [Parameter(Mandatory)]
        [string]$Step
    )

    Write-StepStart `
        -Step $Step `
        -Purpose "Auditar archivos known_hosts sin modificarlos."

    $entries = @(
        Find-LabKnownHostsEntries -Step $Step
    )

    if (-not $entries) {
        Write-StepOk `
            -Step $Step `
            -Message "No se encontraron entradas SSH del laboratorio."

        return @()
    }

    foreach ($entry in $entries) {
        Write-StepWarning `
            -Step $Step `
            -Message "Entrada SSH del laboratorio presente." `
            -Detail (
                "File=$($entry.File); Target=$($entry.Target); " +
                "Matches=$($entry.MatchCount)"
            )
    }

    return $entries
}

function Finish-LabOperation {
    param(
        [int]$ExitCode = 0,
        [switch]$Pause
    )

    $script:LabContext.ExitCode = $ExitCode

    if ($ExitCode -eq 0) {
        Write-LabLog `
            -Level "OK" `
            -Step "END" `
            -Message "La operación terminó correctamente."
    }
    else {
        Write-LabLog `
            -Level "ERROR" `
            -Step "END" `
            -Message "La operación terminó con errores." `
            -Detail "ExitCode=$ExitCode"
    }

    Write-Host ""
    Write-Host "Log detallado:" -ForegroundColor Cyan
    Write-Host $script:LabContext.LogPath -ForegroundColor Cyan
    Write-Host ""

    if ($Pause) {
        [void](Read-Host "Presione Enter para cerrar")
    }

    exit $ExitCode
}
