#!/bin/bash
# =============================================================================
# Script para la configuración inicial del servidor remoto
# Empresa Fintech - Gestión de Infraestructura
# =============================================================================

# Variables de configuración (editar según entorno)
SERVER_IP="${1:-192.168.1.1}"
USERNAME="${2:-admin}"
SSH_KEY="${3:-~/.ssh/id_rsa}"
SSH_PORT="${4:-22}"
LOG_FILE="./logs/setup_$(date +%Y%m%d_%H%M%S).log"

# Colores para salida
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# =============================================================================
# Funciones auxiliares
# =============================================================================

log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo -e "$message" | tee -a "$LOG_FILE"
}

log_success() { log "${GREEN}[OK]${NC} $1"; }
log_error() { log "${RED}[ERROR]${NC} $1"; }
log_warn() { log "${YELLOW}[WARN]${NC} $1"; }

check_exit_code() {
    if [ $? -ne 0 ]; then
        log_error "$1"
        exit 1
    fi
}

# =============================================================================
# Validaciones previas
# =============================================================================

setup_logging() {
    mkdir -p ./logs
    touch "$LOG_FILE"
    log "=== Inicio de configuración del servidor ==="
    log "Servidor: $SERVER_IP | Usuario: $USERNAME | Puerto SSH: $SSH_PORT"
}

validate_prerequisites() {
    log "Validando prerequisitos locales..."

    # Verificar que existe la clave SSH
    if [ ! -f "$(eval echo $SSH_KEY)" ]; then
        log_error "Clave SSH no encontrada en: $SSH_KEY"
        exit 1
    fi
    log_success "Clave SSH encontrada"

    # Verificar conectividad de red
    log "Verificando conectividad con $SERVER_IP..."
    ping -c 3 -W 5 "$SERVER_IP" > /dev/null 2>&1
    check_exit_code "No se puede alcanzar el servidor $SERVER_IP"
    log_success "Conectividad de red verificada"

    # Verificar acceso SSH
    log "Verificando acceso SSH..."
    ssh -i "$SSH_KEY" -p "$SSH_PORT" -o ConnectTimeout=10 -o BatchMode=yes "$USERNAME@$SERVER_IP" "echo 'SSH OK'" > /dev/null 2>&1
    check_exit_code "No se puede establecer conexión SSH con $SERVER_IP"
    log_success "Acceso SSH verificado"
}

# =============================================================================
# Configuración del servidor
# =============================================================================

configure_system_updates() {
    log "Actualizando sistema operativo..."
    ssh -i "$SSH_KEY" -p "$SSH_PORT" "$USERNAME@$SERVER_IP" << 'EOF'
        sudo apt-get update -y && sudo apt-get upgrade -y
        sudo apt-get install -y \
            curl \
            wget \
            vim \
            htop \
            net-tools \
            unattended-upgrades \
            fail2ban \
            ufw \
            logrotate
EOF
    check_exit_code "Fallo al actualizar el sistema"
    log_success "Sistema actualizado e paquetes básicos instalados"
}

configure_ssh_hardening() {
    log "Aplicando hardening SSH..."
    ssh -i "$SSH_KEY" -p "$SSH_PORT" "$USERNAME@$SERVER_IP" << 'EOF'
        # Backup de configuración SSH original
        sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

        # Aplicar configuraciones de seguridad
        sudo sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
        sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
        sudo sed -i 's/#MaxAuthTries 6/MaxAuthTries 3/' /etc/ssh/sshd_config
        sudo sed -i 's/#ClientAliveInterval 0/ClientAliveInterval 300/' /etc/ssh/sshd_config
        sudo sed -i 's/#ClientAliveCountMax 3/ClientAliveCountMax 2/' /etc/ssh/sshd_config

        # Reiniciar servicio SSH
        sudo systemctl restart sshd
EOF
    check_exit_code "Fallo al aplicar hardening SSH"
    log_success "Hardening SSH aplicado"
}

configure_firewall() {
    log "Configurando firewall (UFW)..."
    ssh -i "$SSH_KEY" -p "$SSH_PORT" "$USERNAME@$SERVER_IP" << 'EOF'
        # Configurar reglas básicas
        sudo ufw default deny incoming
        sudo ufw default allow outgoing

        # Permitir SSH
        sudo ufw allow 22/tcp

        # Permitir HTTP/HTTPS (servicios fintech)
        sudo ufw allow 80/tcp
        sudo ufw allow 443/tcp

        # Habilitar firewall
        echo "y" | sudo ufw enable
        sudo ufw status verbose
EOF
    check_exit_code "Fallo al configurar firewall"
    log_success "Firewall configurado y activo"
}

configure_fail2ban() {
    log "Configurando Fail2Ban..."
    ssh -i "$SSH_KEY" -p "$SSH_PORT" "$USERNAME@$SERVER_IP" << 'EOF'
        sudo tee /etc/fail2ban/jail.local << 'JAIL'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
JAIL
        sudo systemctl enable fail2ban
        sudo systemctl restart fail2ban
EOF
    check_exit_code "Fallo al configurar Fail2Ban"
    log_success "Fail2Ban configurado y activo"
}

configure_timezone_and_ntp() {
    log "Configurando zona horaria y sincronización NTP..."
    ssh -i "$SSH_KEY" -p "$SSH_PORT" "$USERNAME@$SERVER_IP" << 'EOF'
        sudo timedatectl set-timezone America/Bogota
        sudo apt-get install -y ntp
        sudo systemctl enable ntp
        sudo systemctl start ntp
EOF
    check_exit_code "Fallo al configurar NTP"
    log_success "Zona horaria y NTP configurados"
}

create_admin_user() {
    log "Creando usuario de administración dedicado..."
    ssh -i "$SSH_KEY" -p "$SSH_PORT" "$USERNAME@$SERVER_IP" << 'EOF'
        # Crear usuario de operaciones si no existe
        if ! id "ops_fintech" &>/dev/null; then
            sudo useradd -m -s /bin/bash -G sudo ops_fintech
            sudo mkdir -p /home/ops_fintech/.ssh
            sudo cp ~/.ssh/authorized_keys /home/ops_fintech/.ssh/
            sudo chown -R ops_fintech:ops_fintech /home/ops_fintech/.ssh
            sudo chmod 700 /home/ops_fintech/.ssh
            sudo chmod 600 /home/ops_fintech/.ssh/authorized_keys
        fi
EOF
    check_exit_code "Fallo al crear usuario de administración"
    log_success "Usuario ops_fintech creado"
}

# =============================================================================
# Ejecución principal
# =============================================================================

main() {
    setup_logging

    echo "=============================================="
    echo "  CONFIGURACIÓN DE SERVIDOR REMOTO - FINTECH"
    echo "=============================================="
    echo ""

    validate_prerequisites
    configure_system_updates
    configure_ssh_hardening
    configure_firewall
    configure_fail2ban
    configure_timezone_and_ntp
    create_admin_user

    echo ""
    log "=============================================="
    log_success "Configuración completada exitosamente"
    log "Log guardado en: $LOG_FILE"
    log "=============================================="
}

# Ejecutar
main
