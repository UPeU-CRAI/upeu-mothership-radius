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
    for f in "$SCRIPT_DIR/instances/"*.env 2>/dev/null; do
        [[ -f "$f" ]] && echo "  - $(basename "$f" .env)"
    done
    echo ""
    err "Especifica el nombre de la sede"
fi

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
