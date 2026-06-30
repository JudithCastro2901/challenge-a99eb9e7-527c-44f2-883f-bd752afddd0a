# Gestión de Infraestructura - Servidores Remotos
# Empresa Fintech

Este proyecto contiene scripts para la gestión automatizada de infraestructura de servidores remotos, incluyendo configuración inicial, monitoreo de recursos y aplicación de parches de seguridad.

## Estructura del Proyecto

```
├── configuracion/
│   └── setup_server.sh        # Configuración inicial del servidor
├── monitoreo/
│   └── monitor_resources.sh   # Monitoreo de recursos en tiempo real
├── parches/
│   └── apply_patches.sh       # Aplicación automatizada de parches
├── documentacion/
│   └── README.md              # Este archivo
└── logs/                      # Directorio de logs (generado automáticamente)
```

## Requisitos

- Sistema operativo Linux/macOS (cliente)
- Acceso SSH al servidor remoto con clave pública configurada
- Permisos sudo en el servidor remoto
- Bash 4.0 o superior

## Configuración

Todos los scripts aceptan parámetros por línea de comandos:

```bash
./script.sh <SERVER_IP> <USERNAME> <SSH_KEY> <SSH_PORT>
```

| Parámetro   | Descripción                  | Valor por defecto  |
|-------------|------------------------------|--------------------|
| SERVER_IP   | Dirección IP del servidor    | 192.168.1.1        |
| USERNAME    | Usuario SSH                  | admin              |
| SSH_KEY     | Ruta a la clave privada SSH  | ~/.ssh/id_rsa      |
| SSH_PORT    | Puerto SSH                   | 22                 |

## Uso

### 1. Configuración Inicial

Configura el servidor con hardening SSH, firewall, Fail2Ban, NTP y paquetes básicos:

```bash
cd configuracion/
chmod +x setup_server.sh
./setup_server.sh 10.0.1.50 admin ~/.ssh/id_rsa 22
```

**Acciones realizadas:**
- Actualización del sistema operativo
- Instalación de paquetes esenciales
- Hardening de SSH (deshabilitar root login, password auth)
- Configuración de firewall (UFW)
- Configuración de Fail2Ban contra fuerza bruta
- Sincronización NTP
- Creación de usuario de operaciones

### 2. Monitoreo de Recursos

Muestra un dashboard con el estado actual del servidor:

```bash
cd monitoreo/
chmod +x monitor_resources.sh
./monitor_resources.sh 10.0.1.50 admin
```

**Recursos monitoreados:**
- CPU (uso porcentual y load average)
- Memoria RAM (total, usado, disponible con barra de progreso)
- Disco (uso por punto de montaje)
- Red (conexiones activas, tráfico RX/TX)
- Servicios críticos (sshd, nginx, ufw, fail2ban)
- Uptime del servidor

**Sistema de alertas:**
- CPU > 80% → Alerta
- RAM > 85% → Alerta
- Disco > 90% → Alerta

### 3. Aplicación de Parches

Proceso seguro de aplicación de parches con backup y rollback:

```bash
cd parches/
chmod +x apply_patches.sh
./apply_patches.sh 10.0.1.50 admin
```

**Proceso:**
1. Validación de conectividad
2. Verificación de parches disponibles
3. Creación de backup pre-parche
4. Aplicación de parches (con confirmación)
5. Verificación post-parche
6. Rollback automático en caso de fallo

## Logs

Todos los scripts generan logs automáticamente en el directorio `./logs/`:

```
logs/
├── setup_20250101_120000.log
├── monitoreo/
│   └── monitor_20250101_130000.log
└── parches/
    └── patches_20250101_140000.log
```

## Seguridad

- Las conexiones se realizan exclusivamente por SSH con clave pública
- No se almacenan contraseñas en los scripts
- El firewall limita el acceso a puertos específicos (22, 80, 443)
- Fail2Ban protege contra ataques de fuerza bruta
- Los backups se crean antes de cualquier modificación del sistema

## Ejecución en Orden Recomendado

```bash
# 1. Configurar el servidor
./configuracion/setup_server.sh <IP> <USER>

# 2. Verificar que todo funciona
./monitoreo/monitor_resources.sh <IP> <USER>

# 3. Aplicar parches de seguridad
./parches/apply_patches.sh <IP> <USER>

# 4. Verificar estado post-parche
./monitoreo/monitor_resources.sh <IP> <USER>
```
