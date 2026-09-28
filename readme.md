<p align="center">
  <img src="assets/logo.png" alt="MikroSafe Backup" width="200">
</p>

Sistema de respaldo automatizado para dispositivos MikroTik mediante SSH/SCP, con contraseñas de respaldo, compresión y notificación por correo electrónico.

---

## 📌 Descripción general

**MikroSafe** es una herramienta de automatización en Bash pensada para entornos de NOC / ISP, cuyo objetivo es extraer de forma confiable los respaldos de configuración de dispositivos MikroTik, empaquetarlos y distribuir los resultados por correo electrónico.

El script fue diseñado con los siguientes criterios:

* Ejecución de tipo "fail-fast"
* Separación clara entre configuración y lógica
* Soporte para autenticación por contraseña (con posibilidad de usar claves SSH)
* Registro de actividad orientado a auditoría
* Protección contra ejecuciones concurrentes mediante un archivo de bloqueo

---

## 🎯 Funciones principales

* Respaldo por lotes de múltiples dispositivos MikroTik
* Soporte para agrupar dispositivos (organización por `GROUP`)
* Filtrado de ejecución por grupo (`--group`)
* Modo de prueba sin conexión real a los equipos (`--dry-run`)
* Reintento con contraseñas alternativas (`sshpass`)
* Compresión automática en ZIP
* Envío por correo electrónico con el respaldo adjunto
* Asunto del correo dinámico según haya o no fallos
* Política de retención y limpieza de logs y respaldos antiguos
* Bloqueo de ejecución (`flock`) para evitar corridas simultáneas por cron
* Validación de permisos del archivo de credenciales
* Ejecución no interactiva, apta para cron

---

## ⚡ Guía rápida

### 🔴 Requisitos previos (OBLIGATORIOS)

Antes de continuar, asegurate de que el servidor donde corre **MikroSafe** pueda establecer una **conexión SSH con cada dispositivo MikroTik de destino**.

Requisitos mínimos:
- Puerto TCP 22 (o el puerto SSH personalizado en uso) accesible desde el servidor de MikroSafe
- IP pública válida o ruteo interno hacia el dispositivo MikroTik
- Reglas de firewall que permitan conexiones SSH entrantes
- Servicio SSH habilitado en el MikroTik
- Credenciales válidas (usuario y contraseña de SSH)

Verificación mínima de conectividad:
```bash
ssh admin@IP_DEL_MIKROTIK
```

1.  **Clonar el repositorio:**
    ```bash
    git clone https://github.com/ffacuDvS/mikrosafe-backup
    cd mikrosafe-backup
    ```

2.  **Configurar el entorno:**
    ```bash
    cp database/credentials.env.example database/credentials.env
    chmod 600 database/credentials.env
    nano database/credentials.env
    # Editar SSH_USER, SSH_PASSWORDS, FROM_EMAIL, etc.
    ```

3.  **Agregar los dispositivos:**
    ```bash
    nano database/mikrosafe-mkts.list
    # Agregar líneas con el formato NOMBRE:IP:GRUPO
    ```

4.  **Configurar el envío de correo (opcional, pero recomendado):**
    ```bash
    nano ~/.msmtprc
    # Configurar los datos de tu servidor SMTP
    chmod 600 ~/.msmtprc
    ```

5.  **Desplegar el script de respaldo en los dispositivos MikroTik (una sola vez):**
    ```bash
    ./deploy_backup_script.sh
    ```

6.  **Ejecutar una prueba manual:**
    ```bash
    ./mikrosafe.sh --dry-run   # Simula la corrida sin conectarse a los equipos
    ./mikrosafe.sh             # Ejecución real
    ```
    Revisá el directorio `outbox/` y tu casilla de correo.

7.  **Programar la ejecución automática:**
    Agregá una tarea cron (ver ejemplo en la sección [Ejemplo de tarea cron](#-ejemplo-de-tarea-cron)).

---

## 🖥️ Uso y opciones de línea de comandos

```bash
./mikrosafe.sh [opciones]
```

| Opción              | Descripción                                                  |
|----------------------|--------------------------------------------------------------|
| `-g, --group <GRUPO>` | Respalda únicamente los dispositivos que pertenecen a `<GRUPO>` |
| `-n, --dry-run`       | Muestra qué haría el script sin conectarse a los equipos      |
| `-v, --version`       | Muestra la versión y termina                                  |
| `-h, --help`          | Muestra la ayuda y termina                                    |

Ejemplos:

```bash
# Respaldar solo el grupo "core"
./mikrosafe.sh --group core

# Simular una corrida completa sin tocar los equipos
./mikrosafe.sh --dry-run
```

---

## 📂 Estructura del proyecto

```
mikrosafe-backup
├── assets
│   ├── mikrosafebackup.rsc
│   ├── email_template.html
│   └── logo.png
├── database
│   ├── credentials.env
│   ├── emails.list
│   ├── mikrosafe-mkts.list
│   ├── error-log.txt
│   └── activity-log.txt
├── deploy_backup_script.sh
├── LICENSE
├── mikrosafe.sh
└── readme.md
```

---

## ⚙️ Requisitos

* Bash >= 4.0
* `scp`
* `sshpass` (para el reintento con contraseñas)
* `flock` (incluido en `util-linux`, usado para el bloqueo de ejecución)
* `zip`
* `msmtp`
* `base64`

---

## 🔐 Modelo de seguridad

### Prioridad de autenticación

1. Claves SSH (si están configuradas y el MikroTik las acepta)
2. Autenticación por contraseña mediante `sshpass`

> Si no hay claves SSH disponibles o el equipo no las soporta, el script funciona **completamente** utilizando las contraseñas definidas en `credentials.env`.

### Manejo de contraseñas

* Las contraseñas nunca se pasan como argumento de línea de comandos (`sshpass -p`), ya que eso las expone en la salida de `ps` a cualquier usuario del sistema. En su lugar, se exportan a través de la variable de entorno `SSHPASS` (`sshpass -e`).
* El script verifica los permisos de `credentials.env` en cada ejecución y advierte si el archivo es legible por otros usuarios además del propietario. Se recomienda mantenerlo en `600`.
* `credentials.env` y los archivos de dependencias sensibles están excluidos del control de versiones mediante `.gitignore`.

### Verificación de host SSH

* `mikrosafe.sh` usa `StrictHostKeyChecking=accept-new`, es decir, confía en la clave del host la primera vez que se conecta y la rechaza si cambia luego (protección básica contra suplantación posterior al primer contacto).
* `deploy_backup_script.sh` deshabilita la verificación de host (`StrictHostKeyChecking=no`) porque se ejecuta una sola vez, sobre equipos recién puestos en producción, para habilitar el script remoto. Si tu entorno lo requiere, podés endurecer esta verificación editando el script.

---

## 🧩 Archivos de configuración

### `deploy_backup_script.sh`

Despliega `assets/mikrosafebackup.rsc` en todos los dispositivos MikroTik listados en `database/mikrosafe-mkts.list`, usando las credenciales de `database/credentials.env`.

### `credentials.env`

Almacenamiento de credenciales basado en variables de entorno.

Ejemplo:

```
SSH_USER=admin
SSH_PASSWORDS="pass1 pass2 pass3"
SSH_TIMEOUT=10
SSH_PORT=22
FROM_EMAIL=mikrosafe@localhost
```

Notas:

* Las contraseñas van separadas por espacios
* Tener varias contraseñas permite manejar rotación de credenciales entre equipos
* El archivo debe tener permisos `600` (`chmod 600 database/credentials.env`)

---

### `mikrosafe-mkts.list`

Lista de dispositivos MikroTik a respaldar.

Formato:

```
NOMBRE:IP:GRUPO
```

Ejemplo:

```
core01:192.168.1.1:core
edge02:192.168.2.1:edges
```

Las líneas vacías y las que comienzan con `#` se ignoran, por lo que podés comentar dispositivos temporalmente sin borrarlos.

---

### `emails.list`

Lista de destinatarios de los reportes de respaldo.

Ejemplo:

```
noc@example.com
admin@example.com
```

Al igual que en `mikrosafe-mkts.list`, las líneas vacías o que comienzan con `#` se ignoran.

---

### `.msmtprc`

Es el archivo de configuración utilizado por `msmtp`, el cliente SMTP encargado de enviar los correos. Normalmente se ubica en `~/.msmtprc`.

Ejemplo:

```
account default
host <HOST_DE_CORREO> # EJEMPLO: smtp.gmail.com
port 587
from <TU_CORREO> # EJEMPLO: ejemplo@dominio.com
auth on
user <TU_CORREO> # EJEMPLO: ejemplo@dominio.com
password <TU_CONTRASEÑA> # EJEMPLO: superclave_123!
tls on
tls_certcheck off
```

Se recomienda ejecutar luego: `chmod 600 ~/.msmtprc`

---

### `mikrosafebackup.rsc`

Este archivo, ubicado en `assets/mikrosafebackup.rsc`, contiene los comandos de RouterOS necesarios para crear y habilitar tanto el script de respaldo como el programador (`scheduler`) responsable de generar exportaciones diarias de la configuración en cada dispositivo MikroTik.

El script realiza las siguientes acciones:

1. Genera un `/export` de la configuración en ejecución
2. Crea un `/system backup save`
3. Programa la ejecución diaria mediante el scheduler de RouterOS

```bash
/system script
remove [find name=mikrosafe_backup]
add name=mikrosafe_backup dont-require-permissions=yes source={
    /export file=mikrosafebackup;
    /system backup save name=mikrosafebackup password=
}
run mikrosafe_backup

/system scheduler
remove [find name=mikrosafe_scheduler]
add name=mikrosafe_scheduler interval=1d start-time=00:05:00 on-event="/system script run mikrosafe_backup" policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon
```

Al ejecutar `deploy_backup_script.sh` (ubicado en la raíz del proyecto), el script recorre todos los dispositivos listados en `database/mikrosafe-mkts.list` y despliega automáticamente el script y el scheduler de RouterOS en cada uno de ellos.
Si solo necesitás agregar un dispositivo nuevo y no querés hacer un barrido completo, podés copiar manualmente el contenido de `mikrosafebackup.rsc` y ejecutarlo directamente en la terminal del MikroTik de destino.

---

## 🚀 Funcionamiento

### 1. Validación del entorno

* Verifica la existencia de los archivos requeridos (`credentials.env`, lista de dispositivos)
* Carga el `.env` de forma segura y advierte si sus permisos son demasiado abiertos
* Aplica el modo estricto de Bash:

  * `-e` corta la ejecución ante cualquier error
  * `-u` protege contra variables no definidas
  * `pipefail` propaga errores dentro de tuberías (`pipe`)
* Adquiere un bloqueo (`flock`) para evitar que dos instancias corran al mismo tiempo (por ejemplo, si una corrida por cron se solapa con una ejecución manual)

---

### 2. Ejecución del respaldo

Para cada dispositivo:

* Se filtran las líneas vacías o comentadas de la lista de dispositivos
* Si se especificó `--group`, solo se procesan los dispositivos de ese grupo
* Se utiliza autenticación por contraseña (mediante la variable de entorno `SSHPASS`, nunca como argumento visible en `ps`)
* Ante un fallo, se reintenta con la siguiente contraseña de la lista
* Los fallos se registran en el log de errores sin detener el resto de la corrida

Los respaldos se almacenan con el siguiente formato de nombre:

```
<GRUPO>_<NOMBRE>_<FECHA>.rsc
```

---

### 3. Compresión

* Todos los respaldos, junto con el log de errores, se comprimen en un ZIP
* El resultado se guarda en `outbox/`

---

### 4. Notificación por correo

* Envía el archivo ZIP como adjunto
* Utiliza MIME multipart
* Compatible con `msmtp`
* El asunto del correo cambia automáticamente si hubo dispositivos con fallas (por ejemplo: "⚠️ MikroSafe – Backup Report (2 failed)")
* Si el envío falla para algún destinatario, se registra en el log de errores sin interrumpir el resto de la ejecución

---

### 5. Política de limpieza

* Conserva los últimos **3 archivos ZIP** en `outbox/`
* Vacía el directorio temporal de respaldos

---

## 🧪 Ejemplo de tarea cron

```
0 2 * * * /ruta/a/mikrosafe/mikrosafe.sh >/dev/null 2>&1
```

---

## 📜 Registro de actividad (logging)

### Log de errores

`database/error-log.txt`

Contiene:

* Marca de tiempo
* Nombre del dispositivo
* Resumen del fallo

---

### Log de actividad

`database/activity-log.txt`

Contiene:

* Marcas de tiempo de cada ejecución
* Confirmación de corridas exitosas, junto con la cantidad de dispositivos respaldados correctamente y con fallas

---

## 📄 Licencia

Licencia MIT

Tenés libertad para:

* Usar
* Modificar
* Distribuir

No estás protegido frente a usos indebidos, ilegales o forks comerciales.

---

## ⚠️ Aviso

Esta herramienta está pensada exclusivamente para **operaciones de auditoría y respaldo autorizadas**.

El autor no asume ninguna responsabilidad por:

* Accesos no autorizados
* Usos indebidos
* Daños causados por un despliegue incorrecto

---

## 🧠 Público destinatario

* ISPs
* Equipos de NOC
* Administradores de red
* Auditores de seguridad

---

## 🔮 Hoja de ruta (propuesta)

* Almacenamiento de respaldos cifrados
* Credenciales por dispositivo
* Panel de control web
* Respaldos firmados con GPG

---

## 👤 Autor

**Facundo Alarcón ( @ffacu.dvs )**
