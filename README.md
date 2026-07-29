# Curso DNS CAMPUS — Máquina de laboratorio 1.1

Este paquete prepara en Windows 11 la máquina virtual utilizada en los laboratorios del **Curso DNS CAMPUS**.

El estudiante solo necesita instalar **Oracle VirtualBox**. No necesita Vagrant, una caja `.box`, un `Vagrantfile` ni realizar configuraciones manuales de red.

## Antes de comenzar

1. Instale Oracle VirtualBox 7.2.x para Windows.
2. Acepte la instalación de sus componentes de red.
3. Reinicie Windows si el instalador de VirtualBox lo solicita.
4. Descargue la appliance `Curso_DNS_Lambda_1.1.ova` desde el enlace entregado por el instructor o desde el LMS.
5. Coloque la OVA en la misma carpeta de estos archivos.
6. No cambie los nombres de los archivos ni ejecute los `.ps1` directamente.

La carpeta debe verse así:

```text
Curso_DNS_Lambda_1.1.ova
SHA256SUMS.txt
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

## Qué hará el instalador

Al ejecutar `INSTALAR_LAB.cmd`, el sistema:

1. solicitará permisos administrativos;
2. comprobará que VirtualBox esté instalado;
3. verificará el SHA-256 de la OVA;
4. comprobará que los puertos y la red del laboratorio estén disponibles;
5. eliminará de `known_hosts` únicamente las entradas antiguas relacionadas con este laboratorio;
6. creará una interfaz privada de VirtualBox para comunicar Windows con Ubuntu;
7. asignará `192.168.10.1/24` a Windows dentro de esa red privada;
8. importará la VM como `Curso-DNS-Lambda`;
9. configurará el acceso SSH `127.0.0.1:2222 → TCP/22`;
10. configurará WebSSH `127.0.0.1:8888 → TCP/8888`;
11. conectará Ubuntu a la dirección fija `192.168.10.53/24`;
12. iniciará la VM en modo Headless;
13. abrirá automáticamente el navegador cuando WebSSH esté listo.

El instalador no crea rutas estáticas, no instala una VPN, no agrega reglas al Firewall de Windows y no instala BIND. BIND se instalará durante los laboratorios cuando el curso lo indique.

## Instalar el laboratorio

Haga doble clic en:

```text
INSTALAR_LAB.cmd
```

Acepte la solicitud de Control de cuentas de usuario de Windows.

No cierre la ventana mientras el instalador está trabajando. Cada paso mostrará su estado y se guardará un registro dentro de:

```text
logs\
```

Cuando finalice correctamente, el navegador abrirá:

```text
http://127.0.0.1:8888/
```

Use estos datos en WebSSH:

```text
Hostname: 127.0.0.1
Port:     22
Username: vagrant
Password: vagrant
```

## Acceso SSH desde Windows

También puede conectarse desde PowerShell o Terminal de Windows:

```powershell
ssh -p 2222 vagrant@127.0.0.1
```

O mediante la red privada del laboratorio:

```powershell
ssh vagrant@192.168.10.53
```

En la primera conexión a una VM recién instalada, OpenSSH puede pedir confirmar la nueva clave del servidor. Revise la huella mostrada y escriba:

```text
yes
```

Los scripts eliminan solamente las claves antiguas asociadas con este laboratorio; no borran los demás servidores guardados en `known_hosts`.

## Uso diario

Para iniciar la VM y abrir WebSSH:

```text
INICIAR_LAB.cmd
```

Para solicitar un apagado correcto de Ubuntu:

```text
DETENER_LAB.cmd
```

No cierre VirtualBox a la fuerza ni apague Windows mientras la VM está escribiendo datos.

## Diagnóstico

Cuando la instalación, el inicio o la red no funcionen, ejecute:

```text
DIAGNOSTICAR_LAB.cmd
```

El diagnóstico no modifica la VM. Comprueba, entre otros elementos:

- versión de VirtualBox;
- OVA y SHA-256;
- estado de la VM;
- adaptadores de red;
- reglas NAT;
- puertos `2222` y `8888`;
- acceso a `192.168.10.53`;
- entradas del laboratorio en `known_hosts`.

El registro queda en `logs\`. Envíe al instructor el archivo de diagnóstico más reciente, no una captura parcial de la ventana.

## Limpiar únicamente las claves SSH antiguas

Cuando SSH muestre:

```text
WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!
```

puede ejecutar:

```text
LIMPIAR_KNOWN_HOSTS_LAB.cmd
```

La herramienta busca y elimina únicamente entradas asociadas con:

```text
[127.0.0.1]:2222
[localhost]:2222
[::1]:2222
192.168.10.53
resolver1
resolver1.lan.home.arpa
curso-dns-lab
curso-dns-lab.lan.home.arpa
curso-dns-lambda
```

No elimina el archivo completo ni las claves de otros equipos.

## Desinstalación completa

Cuando termine el curso, haga doble clic en:

```text
DESINSTALAR_LAB.cmd
```

El desinstalador solicitará confirmación y retirará:

- la VM `Curso-DNS-Lambda`;
- sus discos, configuración y registros propios de VirtualBox;
- sus reglas NAT de los puertos `2222` y `8888`;
- la interfaz Host-Only creada para el laboratorio, cuando ninguna otra VM la utilice;
- el DHCP de VirtualBox asociado, si existe;
- las entradas de `known_hosts` relacionadas con el laboratorio;
- el estado guardado en `%ProgramData%\CursoDNSCampus`.

No elimina:

- Oracle VirtualBox;
- otras máquinas virtuales;
- otras interfaces Host-Only;
- la conexión Wi-Fi o Ethernet;
- archivos personales;
- claves SSH de otros servidores.

Después de desinstalar puede borrar manualmente la carpeta descargada.

## Direcciones del laboratorio

```text
Windows Host-Only: 192.168.10.1/24
Ubuntu:             192.168.10.53/24
SSH por NAT:         127.0.0.1:2222
WebSSH:              127.0.0.1:8888
```

## Credenciales iniciales

```text
Usuario:    vagrant
Contraseña: vagrant
```

Estas credenciales pertenecen exclusivamente a la máquina de práctica.
