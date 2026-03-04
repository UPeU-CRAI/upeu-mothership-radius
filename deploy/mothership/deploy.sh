#!/bin/bash
# ============================================================================
#  deploy-mothership.sh — Despliegue automatizado de la Mothership
#  Uso: scp deploy/ al servidor, luego:
#        cd deploy && sudo bash mothership/deploy.sh
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/templates"
RADIUS_DIR="/etc/freeradius/3.0"
CERTS_DIR="$RADIUS_DIR/certs"

# --- Colores ----------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# --- Cargar .env ------------------------------------------------------------
ENV_FILE="$DEPLOY_DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
    err "No se encontró $ENV_FILE. Copia .env.example a .env y completa los valores."
fi
source "$ENV_FILE"
log "Variables cargadas desde $ENV_FILE"

# --- Verificar variables requeridas -----------------------------------------
REQUIRED_VARS=(
    MOTHERSHIP_HOSTNAME MOTHERSHIP_IP CERT_MODE EAP_DEFAULT_TYPE
    TLS_MIN_VERSION TLS_MAX_VERSION TLS_CIPHER_LIST TLS_ECDH_CURVE
    TLS_CACHE_LIFETIME TLS_CACHE_MAX_ENTRIES
    SAT_NAME SAT_SHORTNAME SAT_PUBLIC_IP
    SECRET_SATELLITE_MOTHERSHIP
    TEST_USER TEST_PASSWORD
)
for var in "${REQUIRED_VARS[@]}"; do
    [[ -z "${!var:-}" ]] && err "Variable requerida $var no está definida en .env"
done
log "Variables validadas"

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

# --- Generar certificados ---------------------------------------------------
if [[ "$CERT_MODE" == "temp" ]]; then
    log "Modo: certificados TEMPORALES (autofirmados)"

    CERT_PRIVATE_KEY="$CERTS_DIR/server-test.key"
    CERT_CERTIFICATE="$CERTS_DIR/server-test.pem"
    CERT_CA_FILE="$CERTS_DIR/server-test.pem"

    if [[ ! -f "$CERT_PRIVATE_KEY" ]]; then
        openssl req -x509 -newkey rsa:2048 \
            -keyout "$CERT_PRIVATE_KEY" \
            -out "$CERT_CERTIFICATE" \
            -days 365 -nodes \
            -subj "/CN=$MOTHERSHIP_HOSTNAME" 2>/dev/null
        chown freerad:freerad "$CERT_PRIVATE_KEY" "$CERT_CERTIFICATE"
        chmod 640 "$CERT_PRIVATE_KEY"
        log "Certificados temporales generados"
    else
        log "Certificados temporales ya existen"
    fi

elif [[ "$CERT_MODE" == "production" ]]; then
    log "Modo: certificados de PRODUCCIÓN (Azure Cloud PKI)"

    CERT_PRIVATE_KEY="$CERTS_DIR/upeu/server-key.pem"
    CERT_CERTIFICATE="$CERTS_DIR/upeu/server-cert.pem"
    CERT_CA_FILE="$CERTS_DIR/upeu/ca-chain.pem"

    for f in "$CERT_PRIVATE_KEY" "$CERT_CERTIFICATE" "$CERT_CA_FILE"; do
        [[ ! -f "$f" ]] && err "Certificado no encontrado: $f"
    done
    log "Certificados de producción verificados"
else
    err "CERT_MODE debe ser 'temp' o 'production'. Valor actual: $CERT_MODE"
fi

# --- Generar DH si no existe ------------------------------------------------
if [[ ! -f "$CERTS_DIR/dh" ]]; then
    warn "Generando parámetros DH (1-2 minutos)..."
    openssl dhparam -out "$CERTS_DIR/dh" 2048 2>/dev/null
    chown freerad:freerad "$CERTS_DIR/dh"
    log "Parámetros DH generados"
else
    log "Parámetros DH ya existen"
fi

# --- Crear directorio de caché TLS ------------------------------------------
mkdir -p /var/log/freeradius/tlscache
chown freerad:freerad /var/log/freeradius/tlscache
chmod 700 /var/log/freeradius/tlscache
log "Directorio de caché TLS listo"

# --- Función de reemplazo de variables en templates -------------------------
apply_template() {
    local src="$1"
    local dst="$2"

    cp "$src" "$dst"

    sed -i "s|%%MOTHERSHIP_HOSTNAME%%|$MOTHERSHIP_HOSTNAME|g" "$dst"
    sed -i "s|%%MOTHERSHIP_IP%%|$MOTHERSHIP_IP|g" "$dst"
    sed -i "s|%%EAP_DEFAULT_TYPE%%|$EAP_DEFAULT_TYPE|g" "$dst"
    sed -i "s|%%CERT_PRIVATE_KEY%%|$CERT_PRIVATE_KEY|g" "$dst"
    sed -i "s|%%CERT_CERTIFICATE%%|$CERT_CERTIFICATE|g" "$dst"
    sed -i "s|%%CERT_CA_FILE%%|$CERT_CA_FILE|g" "$dst"
    sed -i "s|%%TLS_MIN_VERSION%%|$TLS_MIN_VERSION|g" "$dst"
    sed -i "s|%%TLS_MAX_VERSION%%|$TLS_MAX_VERSION|g" "$dst"
    sed -i "s|%%TLS_CIPHER_LIST%%|$TLS_CIPHER_LIST|g" "$dst"
    sed -i "s|%%TLS_ECDH_CURVE%%|$TLS_ECDH_CURVE|g" "$dst"
    sed -i "s|%%TLS_CACHE_LIFETIME%%|$TLS_CACHE_LIFETIME|g" "$dst"
    sed -i "s|%%TLS_CACHE_MAX_ENTRIES%%|$TLS_CACHE_MAX_ENTRIES|g" "$dst"
    sed -i "s|%%SAT_NAME%%|$SAT_NAME|g" "$dst"
    sed -i "s|%%SAT_SHORTNAME%%|$SAT_SHORTNAME|g" "$dst"
    sed -i "s|%%SAT_PUBLIC_IP%%|$SAT_PUBLIC_IP|g" "$dst"
    sed -i "s|%%SECRET_SATELLITE_MOTHERSHIP%%|$SECRET_SATELLITE_MOTHERSHIP|g" "$dst"
    sed -i "s|%%TEST_USER%%|$TEST_USER|g" "$dst"
    sed -i "s|%%TEST_PASSWORD%%|$TEST_PASSWORD|g" "$dst"

    chown freerad:freerad "$dst"
}

# --- Respaldo de configuración actual ---------------------------------------
BACKUP_DIR="/etc/freeradius/3.0/backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -f "$RADIUS_DIR/mods-available/eap" "$BACKUP_DIR/eap" 2>/dev/null || true
cp -f "$RADIUS_DIR/clients.conf" "$BACKUP_DIR/clients.conf" 2>/dev/null || true
cp -f "$RADIUS_DIR/users" "$BACKUP_DIR/users" 2>/dev/null || true
log "Respaldo guardado en $BACKUP_DIR"

# --- Aplicar templates ------------------------------------------------------
apply_template "$TEMPLATES_DIR/eap.conf" "$RADIUS_DIR/mods-available/eap"
log "EAP configurado (modo: $CERT_MODE, tipo: $EAP_DEFAULT_TYPE)"

apply_template "$TEMPLATES_DIR/clients.conf" "$RADIUS_DIR/clients.conf"
log "Clients configurado (satellite: $SAT_NAME @ $SAT_PUBLIC_IP)"

apply_template "$TEMPLATES_DIR/users" "$RADIUS_DIR/users"
log "Users configurado (test: $TEST_USER)"

# --- Habilitar módulo mschap ------------------------------------------------
ln -sf "$RADIUS_DIR/mods-available/mschap" "$RADIUS_DIR/mods-enabled/mschap"
log "Módulo mschap habilitado"

# --- Validar configuración --------------------------------------------------
echo ""
warn "Validando configuración..."
if freeradius -CX 2>&1 | tail -1 | grep -q "Configuration appears to be OK"; then
    log "Configuración validada ✅"
else
    err "Error en la configuración. Ejecutar 'freeradius -CX' para ver detalles."
fi

# --- Reiniciar servicio -----------------------------------------------------
systemctl restart freeradius
systemctl enable freeradius
log "FreeRADIUS reiniciado y habilitado"

# --- Resumen ----------------------------------------------------------------
echo ""
echo "============================================================================"
echo -e " ${GREEN}MOTHERSHIP desplegada exitosamente${NC}"
echo "============================================================================"
echo " Hostname:     $MOTHERSHIP_HOSTNAME"
echo " IP:           $MOTHERSHIP_IP"
echo " Certificados: $CERT_MODE"
echo " EAP:          $EAP_DEFAULT_TYPE"
echo " Satellite:    $SAT_NAME ($SAT_PUBLIC_IP)"
echo " Test user:    $TEST_USER"
echo " Backup:       $BACKUP_DIR"
echo "============================================================================"
echo ""
echo " Siguiente paso: desde el Satellite ejecutar"
echo "   radtest $TEST_USER $TEST_PASSWORD $MOTHERSHIP_IP 0 '<SECRET>'"
echo ""
