#!/bin/bash
# =============================================================================
# Script para el monitoreo de recursos del servidor
# Empresa Fintech - Gestión de Infraestructura
# =============================================================================

# Variables de configuración
SERVER_IP="${1:-192.168.1.1}"
USERNAME="${2:-admin}"
SSH_KEY="${3:-~/.ssh/id_rsa}"
SSH_PORT="${4:-22}"
LOG_DIR="./logs/monitoreo"
LOG_FILE="$LOG_DIR/monitor_$(date +%Y%m%d_%H%M%S).log"

# Umbrales de alerta (porcentajes)
CPU_THRESHOLD=80
RAM_THRESHOLD=85
DISK_THRESHOLD=90

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# =============================================================================
# Funciones auxiliares
# =============================================================================

log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo -e "$message" >> "$LOG_FILE"
}

print_header() {
    echo -e "${BOLD}${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║        MONITOR DE RECURSOS - SERVIDOR FINTECH              ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo -e "║  Servidor: ${SERVER_IP}                                  ║"
    echo -e "║  Fecha:    $(date '+%Y-%m-%d %H:%M:%S')                      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_separator() {
    echo -e "${BLUE}──────────────────────────────────────────────────────────────${NC}"
}

get_status_color() {
    local value=$1
    local threshold=$2
    if [ "$value" -ge "$threshold" ]; then
        echo "${RED}"
    elif [ "$value" -ge $((threshold - 15)) ]; then
        echo "${YELLOW}"
    else
        echo "${GREEN}"
    fi
}

alert() {
    local resource=$1
    local value=$2
    local threshold=$3
    if [ "$value" -ge "$threshold" ]; then
        echo -e "  ${RED}⚠️  ALERTA: $resource al ${value}% (umbral: ${threshold}%)${NC}"
        log "ALERTA: $resource al ${value}% - EXCEDE umbral de ${threshold}%"
    fi
}

# =============================================================================
# Funciones de monitoreo
# =============================================================================

monitor_cpu() {
    echo -e "\n${BOLD}📊 USO DE CPU${NC}"
    print_separator

    local cpu_info=$(ssh -i "$SSH_KEY" -p "$SSH_PORT" -o ConnectTimeout=10 "$USERNAME@$SERVER_IP" << 'EOF'
        # Uso de CPU
        cpu_usage=$(top -b -n 2 -d 1 | grep "Cpu(s)" | tail -1 | awk '{print $2}' | cut -d'%' -f1)
        cpu_cores=$(nproc)
        load_avg=$(cat /proc/loadavg | awk '{print $1, $2, $3}')
        echo "$cpu_usage|$cpu_cores|$load_avg"
EOF
    )

    local cpu_usage=$(echo "$cpu_info" | cut -d'|' -f1 | cut -d'.' -f1)
    local cpu_cores=$(echo "$cpu_info" | cut -d'|' -f2)
    local load_avg=$(echo "$cpu_info" | cut -d'|' -f3)

    local color=$(get_status_color "${cpu_usage:-0}" "$CPU_THRESHOLD")

    echo -e "  Uso de CPU:     ${color}${cpu_usage:-N/A}%${NC}"
    echo -e "  Núcleos:        ${cpu_cores:-N/A}"
    echo -e "  Load Average:   ${load_avg:-N/A}"

    alert "CPU" "${cpu_usage:-0}" "$CPU_THRESHOLD"
    log "CPU: ${cpu_usage}% | Cores: ${cpu_cores} | Load: ${load_avg}"
}

monitor_memory() {
    echo -e "\n${BOLD}🧠 USO DE MEMORIA RAM${NC}"
    print_separator

    local mem_info=$(ssh -i "$SSH_KEY" -p "$SSH_PORT" -o ConnectTimeout=10 "$USERNAME@$SERVER_IP" << 'EOF'
        free -m | awk 'NR==2{printf "%s|%s|%s|%.1f", $2, $3, $7, $3*100/$2}'
EOF
    )

    local total=$(echo "$mem_info" | cut -d'|' -f1)
    local used=$(echo "$mem_info" | cut -d'|' -f2)
    local available=$(echo "$mem_info" | cut -d'|' -f3)
    local percent=$(echo "$mem_info" | cut -d'|' -f4 | cut -d'.' -f1)

    local color=$(get_status_color "${percent:-0}" "$RAM_THRESHOLD")

    echo -e "  Total:          ${total:-N/A} MB"
    echo -e "  Usado:          ${color}${used:-N/A} MB (${percent:-N/A}%)${NC}"
    echo -e "  Disponible:     ${available:-N/A} MB"

    # Barra de progreso
    local bar_width=40
    local filled=$((${percent:-0} * bar_width / 100))
    local empty=$((bar_width - filled))
    printf "  [${color}"
    printf '%0.s█' $(seq 1 $filled 2>/dev/null)
    printf "${NC}"
    printf '%0.s░' $(seq 1 $empty 2>/dev/null)
    printf "] ${percent:-0}%%\n"

    alert "RAM" "${percent:-0}" "$RAM_THRESHOLD"
    log "RAM: ${used}/${total} MB (${percent}%)"
}

monitor_disk() {
    echo -e "\n${BOLD}💾 USO DE DISCO${NC}"
    print_separator

    local disk_info=$(ssh -i "$SSH_KEY" -p "$SSH_PORT" -o ConnectTimeout=10 "$USERNAME@$SERVER_IP" << 'EOF'
        df -h --output=target,size,used,avail,pcent | grep -E "^/" | head -5
EOF
    )

    printf "  %-20s %-10s %-10s %-10s %-8s\n" "Montaje" "Tamaño" "Usado" "Disponible" "Uso%"
    echo "  ─────────────────────────────────────────────────────────"

    while IFS= read -r line; do
        if [ -n "$line" ]; then
            local mount=$(echo "$line" | awk '{print $1}')
            local size=$(echo "$line" | awk '{print $2}')
            local used=$(echo "$line" | awk '{print $3}')
            local avail=$(echo "$line" | awk '{print $4}')
            local percent=$(echo "$line" | awk '{print $5}' | tr -d '%')

            local color=$(get_status_color "${percent:-0}" "$DISK_THRESHOLD")
            printf "  %-20s %-10s %-10s %-10s ${color}%-8s${NC}\n" "$mount" "$size" "$used" "$avail" "${percent}%"

            alert "Disco ($mount)" "${percent:-0}" "$DISK_THRESHOLD"
            log "DISCO $mount: ${used}/${size} (${percent}%)"
        fi
    done <<< "$disk_info"
}

monitor_network() {
    echo -e "\n${BOLD}🌐 ESTADO DE RED${NC}"
    print_separator

    local net_info=$(ssh -i "$SSH_KEY" -p "$SSH_PORT" -o ConnectTimeout=10 "$USERNAME@$SERVER_IP" << 'EOF'
        # Conexiones activas
        connections=$(ss -tun | wc -l)
        established=$(ss -tun state established | wc -l)
        listening=$(ss -tln | wc -l)

        # Tráfico de red (interfaz principal)
        iface=$(ip route | grep default | awk '{print $5}' | head -1)
        rx_bytes=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null || echo 0)
        tx_bytes=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null || echo 0)

        echo "$connections|$established|$listening|$iface|$rx_bytes|$tx_bytes"
EOF
    )

    local connections=$(echo "$net_info" | cut -d'|' -f1)
    local established=$(echo "$net_info" | cut -d'|' -f2)
    local listening=$(echo "$net_info" | cut -d'|' -f3)
    local iface=$(echo "$net_info" | cut -d'|' -f4)
    local rx_bytes=$(echo "$net_info" | cut -d'|' -f5)
    local tx_bytes=$(echo "$net_info" | cut -d'|' -f6)

    # Convertir bytes a formato legible
    local rx_mb=$((${rx_bytes:-0} / 1024 / 1024))
    local tx_mb=$((${tx_bytes:-0} / 1024 / 1024))

    echo -e "  Interfaz:       ${iface:-N/A}"
    echo -e "  Conexiones:     ${connections:-N/A} total | ${established:-N/A} establecidas"
    echo -e "  Puertos:        ${listening:-N/A} en escucha"
    echo -e "  RX (recibido):  ${rx_mb} MB"
    echo -e "  TX (enviado):   ${tx_mb} MB"

    log "RED: ${connections} conexiones | RX: ${rx_mb}MB | TX: ${tx_mb}MB"
}

monitor_services() {
    echo -e "\n${BOLD}⚙️  SERVICIOS CRÍTICOS${NC}"
    print_separator

    local services_info=$(ssh -i "$SSH_KEY" -p "$SSH_PORT" -o ConnectTimeout=10 "$USERNAME@$SERVER_IP" << 'EOF'
        for service in sshd nginx ufw fail2ban; do
            status=$(systemctl is-active $service 2>/dev/null || echo "no-instalado")
            echo "$service:$status"
        done
EOF
    )

    while IFS= read -r line; do
        if [ -n "$line" ]; then
            local svc_name=$(echo "$line" | cut -d':' -f1)
            local svc_status=$(echo "$line" | cut -d':' -f2)

            if [ "$svc_status" = "active" ]; then
                echo -e "  ${GREEN}●${NC} $svc_name: activo"
            elif [ "$svc_status" = "no-instalado" ]; then
                echo -e "  ${YELLOW}○${NC} $svc_name: no instalado"
            else
                echo -e "  ${RED}●${NC} $svc_name: $svc_status"
            fi
        fi
    done <<< "$services_info"
}

monitor_uptime() {
    echo -e "\n${BOLD}⏱️  UPTIME DEL SERVIDOR${NC}"
    print_separator

    local uptime_info=$(ssh -i "$SSH_KEY" -p "$SSH_PORT" -o ConnectTimeout=10 "$USERNAME@$SERVER_IP" "uptime -p")
    echo -e "  Tiempo activo: ${uptime_info:-N/A}"
    log "UPTIME: $uptime_info"
}

# =============================================================================
# Ejecución principal
# =============================================================================

main() {
    # Crear directorio de logs
    mkdir -p "$LOG_DIR"

    # Validar conectividad
    ping -c 1 -W 5 "$SERVER_IP" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: No se puede alcanzar el servidor $SERVER_IP${NC}"
        exit 1
    fi

    # Mostrar dashboard
    clear
    print_header
    log "=== Inicio de monitoreo ==="

    monitor_uptime
    monitor_cpu
    monitor_memory
    monitor_disk
    monitor_network
    monitor_services

    echo ""
    print_separator
    echo -e "${BOLD}Log guardado en:${NC} $LOG_FILE"
    echo -e "${BOLD}Umbrales:${NC} CPU>${CPU_THRESHOLD}% | RAM>${RAM_THRESHOLD}% | Disco>${DISK_THRESHOLD}%"
    print_separator

    log "=== Fin de monitoreo ==="
}

# Ejecutar
main
