function ConvertTo-WindowsCommandLineArgument {
    param(
        [AllowEmptyString()]
        [string]$Argument
    )

    if ($null -eq $Argument -or $Argument.Length -eq 0) {
        return '""'
    }

    if ($Argument -notmatch '[\s"]') {
        return $Argument
    }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0

    foreach ($character in $Argument.ToCharArray()) {
        if ($character -eq '\') {
            $backslashes++
            continue
        }

        if ($character -eq '"') {
            [void]$builder.Append(('\' * (($backslashes * 2) + 1)))
            [void]$builder.Append('"')
            $backslashes = 0
            continue
        }

        if ($backslashes -gt 0) {
            [void]$builder.Append(('\' * $backslashes))
            $backslashes = 0
        }

        [void]$builder.Append($character)
    }

    if ($backslashes -gt 0) {
        [void]$builder.Append(('\' * ($backslashes * 2)))
    }

    [void]$builder.Append('"')
    return $builder.ToString()
}

function ConvertTo-WindowsCommandLine {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    return (
        (
            $Arguments |
                ForEach-Object {
                    ConvertTo-WindowsCommandLineArgument -Argument $_
                }
        ) -join " "
    )
}

function Get-VBoxFailureExplanation {
    param(
        [string]$StdOut,
        [string]$StdErr,
        [int]$ExitCode
    )

    $combined = "$StdOut`n$StdErr"

    if ($combined -match "VBOX_E_OBJECT_NOT_FOUND|Could not find a registered machine") {
        return "VirtualBox no encontró la VM o el objeto solicitado. Verifique el nombre exacto o limpie una instalación parcial."
    }

    if ($combined -match "VERR_NAT_REDIR_SETUP|NAT.*redirect|failed to bind|address already in use") {
        return "El puerto del anfitrión está ocupado o existe otra regla NAT que usa el mismo puerto."
    }

    if ($combined -match "VERR_ALREADY_EXISTS|already exists|Machine settings file.*already exists") {
        return "Ya existe una VM, disco, regla o archivo con el mismo nombre. Hay restos de una instalación anterior."
    }

    if ($combined -match "VBOX_E_INVALID_VM_STATE|current state|machine is not mutable") {
        return "La VM está en un estado que no permite modificarla. Debe estar detenida; el estado 'aborted' sí se trata como detenido."
    }

    if ($combined -match "E_ACCESSDENIED|Access is denied|VERR_ACCESS_DENIED") {
        return "Windows denegó permisos. Ejecute con elevación administrativa y revise antivirus o protección de carpetas."
    }

    if ($combined -match "VERR_INTNET_FLT_IF_NOT_FOUND|host-only.*not found|No such host interface") {
        return "La interfaz Host-Only no existe o el controlador de red de VirtualBox no está disponible."
    }

    if ($combined -match "Cannot register the hard disk|UUID.*already exists") {
        return "VirtualBox ya tiene registrado un disco con el mismo UUID, normalmente por una importación parcial anterior."
    }

    if ($combined -match "Missing or invalid argument to '--nat-pf'") {
        return "Se usó una forma no aceptada para eliminar una regla NAT. VirtualBox 7.2 documenta la eliminación como: --natpf1 delete NOMBRE."
    }

    if ($combined -match "RTGetOpt|Unknown option|Command line option") {
        return "La sintaxis del comando no coincide con la versión de VBoxManage instalada."
    }

    if ($combined -match "VERR_NEM_VM_CREATE_FAILED|VERR_VMX_NO_VMX|VERR_SVM_NO_SVM") {
        return "VirtualBox no pudo iniciar la virtualización. Revise virtualización de firmware, Hyper-V y seguridad basada en virtualización."
    }

    return "VBoxManage devolvió un código distinto de cero. Consulte STDOUT, STDERR y el comando registrado."
}
