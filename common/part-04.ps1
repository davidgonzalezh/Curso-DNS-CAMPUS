function Get-NatRuleByName {
    param(
        [Parameter(Mandatory)]
        [string]$VmName,

        [Parameter(Mandatory)]
        [string]$RuleName,

        [string]$Step = "NAT-LOOKUP"
    )

    $vmInfo = Get-VmInfoMap `
        -Name $VmName `
        -Step $Step `
        -AllowMissing

    if (-not $vmInfo) {
        return $null
    }

    return @(
        Get-ForwardingRules -VmInfo $vmInfo |
            Where-Object {
                $_.Name -eq $RuleName
            }
    )
}

function Remove-NatRuleVerified {
    param(
        [Parameter(Mandatory)]
        [string]$VmName,

        [Parameter(Mandatory)]
        [string]$RuleName,

        [Parameter(Mandatory)]
        [string]$Step
    )

    $existing = @(
        Get-NatRuleByName `
            -VmName $VmName `
            -RuleName $RuleName `
            -Step "$Step-CHECK"
    )

    if (-not $existing) {
        Write-StepOk `
            -Step $Step `
            -Message "La regla NAT '$RuleName' no existe; no hay nada que eliminar."

        return
    }

    Write-StepStart `
        -Step $Step `
        -Purpose "Eliminar la regla NAT '$RuleName' y verificar que desaparezca."

    # Oracle VirtualBox 7.2 documenta esta forma:
    # VBoxManage modifyvm "VM" --natpf1 delete "regla"
    #
    # Se mantienen dos alternativas únicamente como compatibilidad defensiva
    # con distintas variantes del parser de VBoxManage.
    $attempts = @(
        [pscustomobject]@{
            Label = "Oracle-7.2"
            Arguments = @(
                "modifyvm",
                $VmName,
                "--natpf1",
                "delete",
                $RuleName
            )
        },
        [pscustomobject]@{
            Label = "Hyphen-separated"
            Arguments = @(
                "modifyvm",
                $VmName,
                "--nat-pf1",
                "delete",
                $RuleName
            )
        },
        [pscustomobject]@{
            Label = "Equals-fallback"
            Arguments = @(
                "modifyvm",
                $VmName,
                "--nat-pf1=delete=$RuleName"
            )
        }
    )

    $failures = @()

    foreach ($attempt in $attempts) {
        $result = Invoke-VBox `
            -Arguments ([string[]]$attempt.Arguments) `
            -Step "$Step-$($attempt.Label)" `
            -Purpose "eliminar '$RuleName' usando la variante $($attempt.Label)" `
            -AllowFailure

        $remaining = @(
            Get-NatRuleByName `
                -VmName $VmName `
                -RuleName $RuleName `
                -Step "$Step-VERIFY"
        )

        if (-not $remaining) {
            Write-StepOk `
                -Step $Step `
                -Message "Regla NAT '$RuleName' eliminada y verificada." `
                -Detail "Sintaxis=$($attempt.Label)"

            return
        }

        $failures += (
            "$($attempt.Label): ExitCode=$($result.ExitCode); " +
            "Explanation=$($result.Explanation)"
        )
    }

    throw @"
No fue posible eliminar la regla NAT '$RuleName' de '$VmName'.

Se probaron las formas documentadas y de compatibilidad, pero la regla
todavía aparece en showvminfo.

Intentos:
$($failures -join [Environment]::NewLine)
"@
}
