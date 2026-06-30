#!/bin/bash
# =============================================================================
# Script para la aplicación automatizada de parches de seguridad
# Empresa Fintech - Gestión de Infraestructura
# =============================================================================

# Variables de configuración
SERVER_IP="${1:-192.168.1.1}"
USERNAME="${2:-admin}"
SSH_KEY="${3:-~/.ssh/id_rsa}"
SSH_PORT="${4:-22}"
LOG_DIR="./logs/parches"
LOG_FILE="$LOG_DIR/patches_$(date +%Y%m%d_%H%M%S).log"
BACKUP_DIR="/tmp/backup_pre_patch_$(date +%Y%m%d_%H%M%S)"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

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
        return 1
    fi
    return 0
}

print_header() {
    echo -e "${BOLD}${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║     APLICACIÓN DE PARCHES DE SEGURIDAD - FINTECH           ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo -e "║  Servidor: ${SERVER_IP}                                  ║"
    echo -e "║  Fecha:    $(date '+%Y-%m-%d %H:%M:%S')                      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# =============================================================================
# Validaciones previas
# =============================================================================

validate_connection() {
    log "Validando conexión con el servidor..."

    ping -c 2 -W 5 "$SERVER_IP" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        log_error "No se puede alcanzar el servidor $SERVER_IP"
        exit 1
    fi

    ssh -i "$SSH_KEY" -p "$SSH_PORT" -o ConnectTimeout=10 -o BatchMode=yes "$USERNAME@$SERVER_IP" "echo 'ok'" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        log_error "No se puede establecer conexión SSH"
        exit 1
    fi

    log_success "Conexión validada"
}

# =============================================================================
# Verificación de parches disponibles
# =============================================================================

check_available_patches() {
    log "Verificando parches disponibles..."

    local patches_info=$(ssh -i "$SSH_KEY" -p "$SSH_PORT" "$USERNAME@$SERVER_IP" << 'EOF'
        sudo apt-get update -qq 2>/dev/null
        
        # Contar parches de seguridad disponibles
        security_patches=$(apt list --upgradable 2>/dev/null | grep -i security | wc -l)
        total_patches=$(apt list --upgradable 2>/dev/null | grep -v "Listing" | wc -l)
        
        # Listar paquetes de seguridad
        security_list=$(apt list --upgradable 2>/dev/null | grep -i security | head -10)
        
        echo "SECURITY:$security_patches"
        echo "TOTAL:$total_patches"
        echo "LIST:$security_list"
EOF
    )

    local security_count=$(echo "$patches_info" | grep "SECURITY:" | cut -d':' -f2)
    local total_count=$(echo "$patches_info" | grep "TOTAL:" | cut -d':' -f2)

    echo -e "\n${BOLD}📋 PARCHES DISPONIBLES${NC}"
    echo "────────────────────────────────────────"
    echo -e "  Parches de seguridad: ${RED}${security_count:-0}${NC}"
    echo -e "  Parches totales:      ${YELLOW}${total_count:-0}${NC}"
    echo ""

    if [ "${total_count:-0}" -eq 0 ]; then
        log_success "El sistema está actualizado. No hay parches pendientes."
        echo -e "  ${GREEN}✓ El sistema está completamente actualizado${NC}"
        exit 0
    fi

    # Mostrar lista de parches de seguridad
    echo -e "  ${BOLD}Parches de seguridad pendientes:${NC}"
    echo "$patches_info" | grep "LIST:" | cut -d':' -f2- | while IFS= read -r patch; do
        if [ -n "$patch" ]; then
            echo -e "    • $patch"
        fi
    done

    log "Parches encontrados: $security_count de seguridad, $total_count totales"
}

# =============================================================================
# Backup del sistema
# =============================================================================

create_backup() {
    log "Creando backup pre-parche..."

    ssh -i "$SSH_KEY" -p "$SSH_PORT" "$USERNAME@$SERVER_IP" << EOF
        # Crear directorio de backup
        sudo mkdir -p $BACKUP_DIR

        # Backup de la lista de paquetes instalados
        dpkg --get-selections > $BACKUP_DIR/packages_list.txt

        # Backup de configuraciones críticas
        sudo cp -r /etc/apt $BACKUP_DIR/apt_config_backup/
        sudo cp /etc/fstab $BACKUP_DIR/fstab.backup
        sudo cp -r /etc/ssh $BACKUP_DIR/ssh_config_backup/
        sudo cp -r /etc/nginx $BACKUP_DIR/nginx_config_backup/ 2>/dev/null

        # Registrar estado actual del sistema
        uname -a > $BACKUP_DIR/system_info.txt
        df -h >> $BACKUP_DIR/system_info.txt
        systemctl list-units --state=running >> $BACKUP_DIR/system_info.txt

        # Crear snapshot de paquetes con versiones
        apt list --installed 2>/dev/null > $BACKUP_DIR/installed_packages.txt

        echo "Backup completado en: $BACKUP_DIR"
EOF

    if [ $? -ne 0 ]; then
        log_error "Fallo al crear backup"
        echo -e "  ${RED}✗ Error al crear backup. ¿Desea continuar sin backup? (s/n)${NC}"
        read -r response
        if [ "$response" != "s" ]; then
            log "Operación cancelada por el usuario (sin backup)"
            exit 1
        fi
    else
        log_success "Backup creado en: $BACKUP_DIR"
        echo -e "  ${GREEN}✓ Backup creado exitosamente en: $BACKUP_DIR${NC}"
    fi
}

# =============================================================================
# Aplicación de parches
# =============================================================================

apply_security_patches() {
    log "Aplicando parches de seguridad..."
    echo -e "\n${BOLD}🔧 APLICANDO PARCHES${NC}"
    echo "────────────────────────────────────────"

    # Confirmación del usuario
    echo -e "  ${YELLOW}¿Desea aplicar los parches de seguridad? (s/n)${NC}"
    read -r confirm
    if [ "$confirm" != "s" ]; then
        log "Operación cancelada por el usuario"
        echo -e "  ${YELLOW}Operación cancelada${NC}"
        exit 0
    fi

    local patch_result=$(ssh -i "$SSH_KEY" -p "$SSH_PORT" "$USERNAME@$SERVER_IP" << 'EOF'
        # Aplicar solo parches de seguridad
        export DEBIAN_FRONTEND=noninteractive
        
        # Intentar aplicar parches de seguridad primero
        sudo unattended-upgrade --dry-run 2>&1 | tail -5
        
        # Aplicar parches
        sudo apt-get upgrade -y --only-upgrade 2>&1
        
        # Verificar si se necesita reinicio
        if [ -f /var/run/reboot-required ]; then
            echo "REBOOT_REQUIRED:yes"
        else
            echo "REBOOT_REQUIRED:no"
        fi
        
        echo "PATCH_STATUS:$?"
EOF
    )

    local patch_status=$(echo "$patch_result" | grep "PATCH_STATUS:" | cut -d':' -f2)
    local reboot_needed=$(echo "$patch_result" | grep "REBOOT_REQUIRED:" | cut -d':' -f2)

    if [ "${patch_status:-1}" -eq 0 ]; then
        log_success "Parches aplicados correctamente"
        echo -e "  ${GREEN}✓ Parches aplicados exitosamente${NC}"

        if [ "$reboot_needed" = "yes" ]; then
            log_warn "Se requiere reinicio del servidor"
            echo -e "  ${YELLOW}⚠️  Se requiere reinicio del servidor para completar la actualización${NC}"
            echo -e "  ${YELLOW}¿Desea reiniciar ahora? (s/n)${NC}"
            read -r reboot_confirm
            if [ "$reboot_confirm" = "s" ]; then
                ssh -i "$SSH_KEY" -p "$SSH_PORT" "$USERNAME@$SERVER_IP" "sudo reboot"
                log "Servidor reiniciado"
                echo -e "  ${GREEN}Servidor reiniciándose...${NC}"
            fi
        fi
    else
        log_error "Error al aplicar parches"
        echo -e "  ${RED}✗ Error al aplicar parches. Iniciando rollback...${NC}"
        rollback
    fi
}

# =============================================================================
# Rollback
# =============================================================================

rollback() {
    log_warn "Iniciando proceso de rollback..."
    echo -e "\n${BOLD}${RED}🔄 ROLLBACK${NC}"
    echo "────────────────────────────────────────"

    ssh -i "$SSH_KEY" -p "$SSH_PORT" "$USERNAME@$SERVER_IP" << EOF
        # Restaurar lista de paquetes desde backup
        if [ -f "$BACKUP_DIR/packages_list.txt" ]; then
            echo "Restaurando paquetes desde backup..."
            sudo dpkg --set-selections < $BACKUP_DIR/packages_list.txt
            sudo apt-get dselect-upgrade -y
        fi

        # Restaurar configuraciones
        if [ -d "$BACKUP_DIR/ssh_config_backup" ]; then
            sudo cp -r $BACKUP_DIR/ssh_config_backup/* /etc/ssh/
            sudo systemctl restart sshd
        fi

        if [ -d "$BACKUP_DIR/nginx_config_backup" ]; then
            sudo cp -r $BACKUP_DIR/nginx_config_backup/* /etc/nginx/ 2>/dev/null
            sudo systemctl restart nginx 2>/dev/null
        fi

        echo "Rollback completado"
EOF

    if [ $? -eq 0 ]; then
        log_success "Rollback completado exitosamente"
        echo -e "  ${GREEN}✓ Rollback completado. Sistema restaurado al estado anterior.${NC}"
    else
        log_error "Fallo en el rollback. Intervención manual requerida."
        echo -e "  ${RED}✗ Error en rollback. Se requiere intervención manual.${NC}"
        echo -e "  ${RED}  Backup disponible en: $BACKUP_DIR${NC}"
    fi
}

# =============================================================================
# Verificación post-parche
# =============================================================================

verify_post_patch() {
    log "Verificando estado post-parche..."
    echo -e "\n${BOLD}✅ VERIFICACIÓN POST-PARCHE${NC}"
    echo "────────────────────────────────────────"

    local verify_result=$(ssh -i "$SSH_KEY" -p "$SSH_PORT" "$USERNAME@$SERVER_IP" << 'EOF'
        # Verificar servicios críticos
        echo "=== SERVICIOS ==="
        for svc in sshd nginx ufw fail2ban; do
            status=$(systemctl is-active $svc 2>/dev/null || echo "N/A")
            echo "$svc:$status"
        done

        # Verificar conectividad
        echo "=== CONECTIVIDAD ==="
        ping -c 1 8.8.8.8 > /dev/null 2>&1 && echo "internet:ok" || echo "internet:fail"

        # Verificar espacio en disco
        echo "=== DISCO ==="
        df -h / | tail -1 | awk '{print "root_disk:" $5}'

        # Verificar parches pendientes restantes
        echo "=== PENDIENTES ==="
        remaining=$(apt list --upgradable 2>/dev/null | grep -v "Listing" | wc -l)
        echo "remaining:$remaining"
EOF
    )

    # Mostrar resultados
    echo "$verify_result" | grep -v "===" | while IFS=: read -r key value; do
        if [ -n "$key" ] && [ -n "$value" ]; then
            if [ "$value" = "active" ] || [ "$value" = "ok" ]; then
                echo -e "  ${GREEN}●${NC} $key: $value"
            elif [ "$value" = "N/A" ]; then
                echo -e "  ${YELLOW}○${NC} $key: no instalado"
            else
                echo -e "  ${RED}●${NC} $key: $value"
            fi
        fi
    done

    log_success "Verificación post-parche completada"
}

# =============================================================================
# Ejecución principal
# =============================================================================

main() {
    # Crear directorio de logs
    mkdir -p "$LOG_DIR"

    print_header
    log "=== Inicio del proceso de parcheo ==="
    log "Servidor: $SERVER_IP | Usuario: $USERNAME"

    # Paso 1: Validar conexión
    validate_connection

    # Paso 2: Verificar parches disponibles
    check_available_patches

    # Paso 3: Crear backup
    create_backup

    # Paso 4: Aplicar parches
    apply_security_patches

    # Paso 5: Verificación post-parche
    verify_post_patch

    echo ""
    echo "────────────────────────────────────────"
    log "=== Proceso de parcheo finalizado ==="
    log "Log completo en: $LOG_FILE"
    echo -e "${BOLD}Log guardado en:${NC} $LOG_FILE"
    echo -e "${BOLD}Backup en servidor:${NC} $BACKUP_DIR"
    echo "────────────────────────────────────────"
}

# Ejecutar
main
