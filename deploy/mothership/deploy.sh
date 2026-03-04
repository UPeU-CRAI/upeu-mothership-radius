#!/bin/bash
# ============================================================================
#  deploy-mothership.sh — Despliegue automatizado de la Mothership
#  Uso: cd deploy && sudo bash mothership/deploy.sh
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
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info() { echo -e "${CYAN}[i]${NC} $1"; }

# --- Cargar variables -------------------------------------------------------
GLOBAL_ENV="$DEPLOY_DIR/global.env"
LOCAL_ENV="$SCRIPT_DIR/.env"

[[ ! -f "$GLOBAL_ENV" ]] && err "No se encontró $GLOBAL_ENV"
[[ ! -f "$LOCAL_ENV" ]] && err "No se encontró $LOCAL_ENV. Copia .env.example a .env y completa los valores."

source "$GLOBAL_ENV"
source "$LOCAL_ENV"
log "Variables cargadas (global + mothership)"

# --- Verificar variables requeridas -----------------------------------------
REQUIRED_VARS=(
    MOTHERSHIP_HOSTNAME MOTHERSHIP_IP CERT_MODE EAP_DEFAULT_TYPE
    TLS_MIN_VERSION TLS_MAX_VERSION TLS_CIPHER_LIST TLS_ECDH_CURVE
    TLS_CACHE_LIFETIME TLS_CACHE_MAX_ENTRIES
    SAT_1_NAME SAT_1_PUBLIC_IP SAT_1_SECRET
    TEST_USER TEST_PASSWORD
)
for var in "${REQUIRED_VARS[@]}"; do
    [[ -z "${!var:-}" ]] && err "Variable requerida $var no está definida"
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
    err "CERT_MODE debe ser 'temp' o 'production'. Valor: $CERT_MODE"
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

# --- Generar bloques de clients para cada Satellite -------------------------
generate_satellite_clients() {
    local clients=""
    local i=1

    while true; do
        local name_var="SAT_${i}_NAME"
        local shortname_var="SAT_${i}_SHORTNAME"
        local ip_var="SAT_${i}_PUBLIC_IP"
        local secret_var="SAT_${i}_SECRET"

        # Si no existe SAT_N_NAME, terminamos
        [[ -z "${!name_var:-}" ]] && break

        local name="${!name_var}"
        local shortname="${!shortname_var:-$name}"
        local ip="${!ip_var}"
        local secret="${!secret_var}"

        [[ -z "$ip" ]] && err "SAT_${i}_PUBLIC_IP no definida para $name"
        [[ -z "$secret" ]] && err "SAT_${i}_SECRET no definida para $name"

        clients+="# Satellite: $name
client $shortname {
    ipaddr    = $ip
    secret    = '$secret'
    shortname = $shortname
    require_message_authenticator = yes
}

"
        info "  Satellite $i: $name ($ip)"
        ((i++))
    done

    echo "$clients"
}

# --- Aplicar template EAP ---------------------------------------------------
apply_eap_template() {
    local dst="$RADIUS_DIR/mods-available/eap"
    cp "$TEMPLATES_DIR/eap.conf" "$dst"

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

    chown freerad:freerad "$dst"
}

# --- Aplicar template clients.conf ------------------------------------------
apply_clients_template() {
    local dst="$RADIUS_DIR/clients.conf"
    local sat_clients
    sat_clients=$(generate_satellite_clients)

    cp "$TEMPLATES_DIR/clients.conf" "$dst"

    # Reemplazar el placeholder con los bloques generados
    # Usamos un archivo temporal porque sed no maneja bien multilínea
    local tmpfile
    tmpfile=$(mktemp)
    echo "$sat_clients" > "$tmpfile"
    sed -i "/%%SATELLITE_CLIENTS%%/r $tmpfile" "$dst"
    sed -i "/%%SATELLITE_CLIENTS%%/d" "$dst"
    rm -f "$tmpfile"

    chown freerad:freerad "$dst"
}

# --- Aplicar template users -------------------------------------------------
apply_users_template() {
    local dst="$RADIUS_DIR/users"
    cp "$TEMPLATES_DIR/users" "$dst"

    sed -i "s|%%TEST_USER%%|$TEST_USER|g" "$dst"
    sed -i "s|%%TEST_PASSWORD%%|$TEST_PASSWORD|g" "$dst"

    chown freerad:freerad "$dst"
}

# --- Respaldo ---------------------------------------------------------------
BACKUP_DIR="$RADIUS_DIR/backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -f "$RADIUS_DIR/mods-available/eap" "$BACKUP_DIR/eap" 2>/dev/null || true
cp -f "$RADIUS_DIR/clients.conf" "$BACKUP_DIR/clients.conf" 2>/dev/null || true
cp -f "$RADIUS_DIR/users" "$BACKUP_DIR/users" 2>/dev/null || true
log "Respaldo guardado en $BACKUP_DIR"

# --- Aplicar ----------------------------------------------------------------
echo ""
info "Registrando Satellites:"
apply_eap_template
log "EAP configurado (modo: $CERT_MODE, tipo: $EAP_DEFAULT_TYPE)"

apply_clients_template
log "Clients configurado con todos los Satellites"

apply_users_template
log "Users configurado (test: $TEST_USER)"

# --- Habilitar módulo mschap ------------------------------------------------
ln -sf "$RADIUS_DIR/mods-available/mschap" "$RADIUS_DIR/mods-enabled/mschap"
log "Módulo mschap habilitado"

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
echo -e " ${GREEN}MOTHERSHIP desplegada exitosamente${NC}"
echo "============================================================================"
echo " Hostname:     $MOTHERSHIP_HOSTNAME"
echo " IP:           $MOTHERSHIP_IP"
echo " Certificados: $CERT_MODE"
echo " EAP:          $EAP_DEFAULT_TYPE"
echo " Test user:    $TEST_USER"
echo " Backup:       $BACKUP_DIR"
echo "============================================================================"
