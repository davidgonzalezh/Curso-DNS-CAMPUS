# Curso DNS CAMPUS — Máquina de laboratorio 1.1

Esta carpeta instala en Windows 11 la máquina virtual utilizada en los laboratorios del **Curso DNS CAMPUS**.

La instalación es automática. El estudiante no necesita Vagrant, archivos `.box`, un `Vagrantfile` ni configurar manualmente las interfaces de VirtualBox.

## 1. Requisitos

Antes de comenzar, compruebe lo siguiente:

1. Windows 11 de 64 bits.
2. Virtualización habilitada en el firmware del equipo.
3. Oracle VirtualBox 7.2.x instalado con sus controladores de red.
4. Al menos 4 GB de memoria disponibles para la VM.
5. Espacio libre suficiente para importar el disco virtual.
6. Permisos para aprobar la solicitud UAC de Windows.
7. La appliance `Curso_DNS_Lambda_1.1.ova` descargada desde el LMS o desde el medio entregado por el instructor.

Reinicie Windows cuando la instalación o actualización de VirtualBox lo solicite.

## 2. Preparar la carpeta

Coloque la OVA en la misma carpeta de los scripts. No cambie los nombres de los archivos y no ejecute directamente los archivos `.ps1`.

La carpeta debe contener como mínimo:

```text
Curso_DNS_Lambda_1.1.ova
SHA256SUMS.txt
README.md
INSTALAR_LAB.cmd
INICIAR_LAB.cmd
DETENER_LAB.cmd
DESINSTALAR_LAB.cmd
DIAGNOSTICAR_LAB.cmd
LIMPIAR_KNOWN_HOSTS_LAB.cmd
curso-dns-common.ps1
instalar-lab.ps1
iniciar-lab.ps1
detener-lab.ps1
desinstalar-lab.ps1
diagnosticar-lab.ps1
limpiar-known-hosts-lab.ps1
```

## 3. Diagnóstico previo

El diagnóstico es de solo lectura. No instala ni elimina máquinas virtuales.

Ejecute:

```text
DIAGNOSTICAR_LAB.cmd
```

Puede finalizar con alguno de estos resultados:

### `RESULTADO: LISTO PARA INSTALAR`

No se detectó un bloqueo ni una corrección pendiente.

### `RESULTADO: LISTO CON CORRECCIONES INTERACTIVAS`

El instalador puede continuar, pero mostrará una decisión antes de modificar el elemento detectado. Algunos ejemplos son una interfaz Host-Only preexistente, otra red en `192.168.10.0/24`, una VM activa, una instalación parcial o un puerto ocupado.

### `RESULTADO: NO LISTO PARA INSTALAR`

Existe un problema que el instalador no debe intentar corregir automáticamente, por ejemplo una OVA ausente o dañada, un SHA-256 incorrecto o una versión de VirtualBox fuera de la rama 7.2.x. El registro explica el bloqueo exacto.

El diagnóstico y el instalador usan la misma evaluación de red. El diagnóstico no modifica el equipo.

Los registros se guardan en:

```text
logs\
```

## 4. Instalar

Haga doble clic en:

```text
INSTALAR_LAB.cmd
```

Apruebe la solicitud de Control de cuentas de usuario. No cierre la ventana durante el proceso.

El instalador:

1. verifica VirtualBox;
2. verifica el SHA-256 de la OVA;
3. inspecciona la appliance con `VBoxManage import --dry-run`;
4. revisa instalaciones incompletas;
5. revisa la red `192.168.10.0/24`;
6. revisa los puertos `2222` y `8888`;
7. elimina únicamente entradas SSH antiguas relacionadas con este laboratorio;
8. crea o reutiliza una interfaz VirtualBox Host-Only compatible;
9. importa la VM como `Curso-DNS-Lambda`;
10. configura NAT, SSH y WebSSH;
11. inicia la VM en modo Headless;
12. verifica los tres accesos del laboratorio.

## 5. Preguntas que puede mostrar el instalador

### 5.1 Ya existe una interfaz VirtualBox Host-Only compatible

El instalador identifica la interfaz por la información de VirtualBox, su GUID, su dirección y la interfaz correspondiente en Windows. El nombre visible en Windows puede ser `Ethernet 4` aunque VirtualBox la muestre como `VirtualBox Host-Only Ethernet Adapter`.

Opciones:

```text
A = usar la interfaz existente — recomendado
N = eliminarla y crear una nueva
C = cancelar
```

Al elegir **A**:

- la interfaz se reutiliza;
- no se elimina;
- no se modifica su DHCP porque no fue creada por este instalador;
- el desinstalador la conservará.

Al elegir **N**, el script mostrará las VM que la utilizan, ofrecerá apagarlas correctamente y solicitará confirmación antes de desconectarlas y retirar la interfaz.

### 5.2 Existen varias interfaces VirtualBox Host-Only compatibles

Cuando hay más de una interfaz que coincide con `192.168.10.1/24`, el script no elige una arbitrariamente. Muestra las interfaces y ofrece:

```text
N = eliminar las interfaces compatibles confirmadas y crear una nueva
R = corregirlas manualmente y volver a evaluar
C = cancelar sin eliminarlas
```

Antes de eliminar una interfaz, el instalador identifica las VM que la utilizan y ofrece apagarlas correctamente.

### 5.3 Otra interfaz usa `192.168.10.0/24`

Puede tratarse de una LAN física, una VPN o un adaptador de otra plataforma. El script **no la elimina automáticamente**.

Opciones:

```text
D = deshabilitar temporalmente el adaptador durante el laboratorio
R = reintentar después de cambiar su dirección o desconectarlo
C = cancelar sin modificarlo
```

La opción **D** puede interrumpir la conectividad de ese adaptador. El instalador muestra su nombre, descripción, índice y GUID antes de deshabilitarlo. El desinstalador lo vuelve a habilitar. Si la instalación falla después de deshabilitarlo, el instalador intenta restaurarlo antes de salir.

La red de la appliance no puede cambiarse desde el instalador porque Ubuntu usa de forma fija `192.168.10.53/24` en los laboratorios del curso.

### 5.4 Una VM necesaria está encendida

El script muestra la VM y ofrece:

```text
A = solicitar apagado correcto mediante ACPI
F = forzar apagado
C = cancelar
```

Use **A** primero. El apagado forzado equivale a cortar la alimentación y solo debe usarse cuando el sistema invitado no responde.

### 5.5 Los puertos `2222` o `8888` están ocupados

El script muestra el PID y el proceso correspondiente y ofrece:

```text
R = cerrar el proceso manualmente y reintentar
T = terminar el proceso mostrado
C = cancelar
```

No termina procesos sin confirmación.

### 5.6 Existe una instalación parcial

El script muestra el estado de `Curso-DNS-Lambda` y ofrece eliminarla antes de volver a importar la OVA. No elimina otras VM por coincidencias parciales.

## 6. Resultado esperado

La instalación solo termina correctamente cuando responden:

```text
SSH por NAT: 127.0.0.1:2222
WebSSH:      127.0.0.1:8888
SSH directo: 192.168.10.53:22
```

El navegador abrirá:

```text
http://127.0.0.1:8888/
```

Credenciales iniciales:

```text
Hostname: 127.0.0.1
Port:     22
Username: vagrant
Password: vagrant
```

## 7. Acceso por Terminal o PowerShell

Por NAT:

```powershell
ssh -p 2222 vagrant@127.0.0.1
```

Por la red privada:

```powershell
ssh vagrant@192.168.10.53
```

En la primera conexión puede solicitar la confirmación de la nueva clave SSH. Las entradas antiguas del laboratorio se eliminan selectivamente; no se borra el archivo completo `known_hosts`.

## 8. Uso diario

Para iniciar la VM y abrir WebSSH:

```text
INICIAR_LAB.cmd
```

Para solicitar un apagado correcto de Ubuntu:

```text
DETENER_LAB.cmd
```

No apague Windows mientras la VM esté escribiendo en disco.

## 9. Limpiar únicamente las claves SSH del laboratorio

Cuando aparezca:

```text
WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!
```

Ejecute:

```text
LIMPIAR_KNOWN_HOSTS_LAB.cmd
```

La herramienta revisa únicamente las identidades usadas por el laboratorio, incluidas `[127.0.0.1]:2222`, `192.168.10.53`, `resolver1` y `resolver1.lan.home.arpa`. No elimina claves de otros servidores.

## 10. Desinstalación

Ejecute:

```text
DESINSTALAR_LAB.cmd
```

El desinstalador retira:

- `Curso-DNS-Lambda` y sus discos;
- sus reglas NAT;
- la interfaz Host-Only cuando fue creada por el instalador y ninguna otra VM la usa;
- las entradas SSH del laboratorio;
- el estado guardado en `%ProgramData%\CursoDNSCampus`;
- y vuelve a habilitar los adaptadores que el instalador haya deshabilitado temporalmente.

Si la instalación reutilizó una interfaz Host-Only preexistente, esa interfaz se conserva.

No elimina VirtualBox, otras VM, archivos personales, Wi-Fi, Ethernet ni claves SSH ajenas al laboratorio.

## 11. Solicitar soporte

No envíe solamente una captura de la ventana. Adjunte el archivo más reciente de la operación correspondiente:

```text
logs\diagnostico-*.log
logs\instalacion-*.log
logs\desinstalacion-*.log
logs\inicio-*.log
logs\detencion-*.log
```

Incluya también qué opción eligió cuando el script mostró una decisión interactiva.
