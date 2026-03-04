#!/bin/bash
# ============================================================================
#  deploy-satellite.sh — Despliegue automatizado del Satellite
#  Uso: cd deploy && sudo bash satellite/deploy.sh <nombre_sede>
#  Ejemplo: sudo bash satellite/deploy.sh lima
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/templates"
RADIUS_DIR="/etc/freeradius/3.0"

# --- Colores ----------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info() { echo -e "${CYAN}[i]${NC} $1"; }

# --- Verificar argumento de sede --------------------------------------------
INSTANCE="${1:-}"
if [[ -z "$INSTANCE" ]]; then
    echo ""
    echo "Uso: sudo bash satellite/deploy.sh <nombre_sede>"
    echo ""
    echo "Instancias disponibles:"
    if [[ -d "$SCRIPT_DIR/instances" ]]; then
        for f in "$SCRIPT_DIR/instances/"*.env; do
            [[ -f "$f" ]] && echo "  - $(basename "$f" .env)"
        done
    else
        echo "  (ninguna — crear instances/<sede>.env)"
    fi
    echo ""
    err "Especifica el nombre de la sede"
fi

# Crear directorio instances si no existe
mkdir -p "$SCRIPT_DIR/instances"

INSTANCE_ENV="$SCRIPT_DIR/instances/${INSTANCE}.env"
[[ ! -f "$INSTANCE_ENV" ]] && err "No se encontró $INSTANCE_ENV"

# --- Cargar variables -------------------------------------------------------
GLOBAL_ENV="$DEPLOY_DIR/global.env"
[[ ! -f "$GLOBAL_ENV" ]] && err "No se encontró $GLOBAL_ENV"

source "$GLOBAL_ENV"
source "$INSTANCE_ENV"
log "Variables cargadas (global + $INSTANCE)"

# --- Verificar variables requeridas -----------------------------------------
REQUIRED_VARS=(
    MOTHERSHIP_IP
    SAT_NAME SAT_LOCAL_IP
    SECRET_SATELLITE_MOTHERSHIP SECRET_AP_SATELLITE
    AP_SUBNET AP_SHORTNAME
    PROXY_RESPONSE_WINDOW PROXY_ZOMBIE_PERIOD PROXY_REVIVE_INTERVAL
    TEST_USER TEST_PASSWORD
)
for var in "${REQUIRED_VARS[@]}"; do
    [[ -z "${!var:-}" ]] && err "Variable requerida $var no está definida"
done
log "Variables validadas para sede: $INSTANCE"

# --- Instalar FreeRADIUS si no existe ---------------------------------------
if ! command -v freeradius &>/dev/null; then
    warn "FreeRADIUS no instalado. Instalando..."
    apt-get update -qq
    apt-get install -y -qq freeradius freeradius-utils
    systemctl stop freeradius
    log "FreeRADIUS instalado"
else
    log "FreeRADIUS ya instalado ($(freeradius -v | head -1))"
fi

# --- Función de reemplazo ---------------------------------------------------
apply_template() {
    local src="$1"
    local dst="$2"

    cp "$src" "$dst"

    sed -i "s|%%MOTHERSHIP_IP%%|$MOTHERSHIP_IP|g" "$dst"
    sed -i "s|%%SAT_NAME%%|$SAT_NAME|g" "$dst"
    sed -i "s|%%SAT_LOCAL_IP%%|$SAT_LOCAL_IP|g" "$dst"
    sed -i "s|%%SECRET_SATELLITE_MOTHERSHIP%%|$SECRET_SATELLITE_MOTHERSHIP|g" "$dst"
    sed -i "s|%%SECRET_AP_SATELLITE%%|$SECRET_AP_SATELLITE|g" "$dst"
    sed -i "s|%%AP_SUBNET%%|$AP_SUBNET|g" "$dst"
    sed -i "s|%%AP_SHORTNAME%%|$AP_SHORTNAME|g" "$dst"
    sed -i "s|%%PROXY_RESPONSE_WINDOW%%|$PROXY_RESPONSE_WINDOW|g" "$dst"
    sed -i "s|%%PROXY_ZOMBIE_PERIOD%%|$PROXY_ZOMBIE_PERIOD|g" "$dst"
    sed -i "s|%%PROXY_REVIVE_INTERVAL%%|$PROXY_REVIVE_INTERVAL|g" "$dst"
    sed -i "s|%%PROXY_RESPONSE_TIMEOUTS%%|${PROXY_RESPONSE_TIMEOUTS:-3}|g" "$dst"

    # --- Lógica de Backup Server ---
    local backup_ip="${MOTHERSHIP_BACKUP_IP:-}"
    local backup_secret="${MOTHERSHIP_BACKUP_SECRET:-$SECRET_SATELLITE_MOTHERSHIP}"
    
    if [[ -n "$backup_ip" ]]; then
        sed -i "s|%%BACKUP_SERVER_REF%%|home_server = upeu-aws-mothership-backup|g" "$dst"
        
        local backup_block="
home_server upeu-aws-mothership-backup {
    type = auth+acct
    ipaddr = $backup_ip
    port = 1812
    secret = '$backup_secret'
    require_message_authenticator = yes
    response_window = $PROXY_RESPONSE_WINDOW
    zombie_period = $PROXY_ZOMBIE_PERIOD
    revive_interval = $PROXY_REVIVE_INTERVAL
    status_check = status-server
    check_interval = 30
    check_timeout = 3
    num_answers_to_alive = 3
    max_outstanding = 65536
    coa { irt = 2; mrt = 16; mrc = 5; mrd = 30 }
    limit { max_connections = 16; max_requests = 0; lifetime = 0; idle_timeout = 0 }
}"
        # Inyectar el bloque de backup (usando un archivo temporal para escapar caracteres)
        local tmpblock=$(mktemp)
        echo "$backup_block" > "$tmpblock"
        sed -i "/%%BACKUP_SERVER_BLOCK%%/r $tmpblock" "$dst"
        rm -f "$tmpblock"
    fi
    
    # Limpiar placeholders si no hay backup
    sed -i "s|%%BACKUP_SERVER_REF%%||g" "$dst"
    sed -i "/%%BACKUP_SERVER_BLOCK%%/d" "$dst"

    chown freerad:freerad "$dst"
}

# --- Respaldo ---------------------------------------------------------------
BACKUP_DIR="$RADIUS_DIR/backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -f "$RADIUS_DIR/proxy.conf" "$BACKUP_DIR/proxy.conf" 2>/dev/null || true
cp -f "$RADIUS_DIR/clients.conf" "$BACKUP_DIR/clients.conf" 2>/dev/null || true
log "Respaldo guardado en $BACKUP_DIR"

# --- Aplicar templates ------------------------------------------------------
apply_template "$TEMPLATES_DIR/proxy.conf" "$RADIUS_DIR/proxy.conf"
log "Proxy configurado (mothership: $MOTHERSHIP_IP)"

apply_template "$TEMPLATES_DIR/clients.conf" "$RADIUS_DIR/clients.conf"
log "Clients configurado (APs: $AP_SUBNET)"

# --- Validar ----------------------------------------------------------------
echo ""
warn "Validando configuración..."
if freeradius -CX 2>&1 | tail -1 | grep -q "Configuration appears to be OK"; then
    log "Configuración validada ✅"
else
    err "Error en la configuración. Ejecutar 'freeradius -CX' para detalles."
fi

# --- Reiniciar --------------------------------------------------------------
systemctl restart freeradius
systemctl enable freeradius
log "FreeRADIUS reiniciado y habilitado"

# --- Resumen ----------------------------------------------------------------
echo ""
echo "============================================================================"
echo -e " ${GREEN}SATELLITE desplegado exitosamente${NC}"
echo "============================================================================"
echo " Sede:         $INSTANCE"
echo " Nombre:       $SAT_NAME"
echo " IP local:     $SAT_LOCAL_IP"
echo " Mothership:   $MOTHERSHIP_IP"
echo " APs subnet:   $AP_SUBNET"
echo " Backup:       $BACKUP_DIR"
echo "============================================================================"
echo ""
echo " Verificar el túnel:"
echo "   radtest $TEST_USER $TEST_PASSWORD 127.0.0.1 0 testing123"
echo ""
