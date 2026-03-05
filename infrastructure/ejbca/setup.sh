#!/bin/bash
# =============================================================================
# Script de Setup Inicial — EJBCA CE en AWS EC2
# UPeU CRAI — PKI para FreeRADIUS + Intune
# =============================================================================
# Ejecutar como root o con sudo en una EC2 Ubuntu 24.04 limpia
# Uso: sudo bash setup.sh
# =============================================================================

set -e

echo "=========================================="
echo "  EJBCA CE — Setup Inicial en AWS EC2"
echo "  UPeU CRAI — PKI Infrastructure"
echo "=========================================="

# --- Paso 1: Actualizar sistema ---
echo ""
echo "[1/5] Actualizando sistema..."
apt update && apt upgrade -y

# --- Paso 2: Instalar Docker ---
echo ""
echo "[2/5] Instalando Docker..."
apt install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Agregar usuario ubuntu al grupo docker
usermod -aG docker ubuntu

# --- Paso 3: Instalar Certbot ---
echo ""
echo "[3/5] Instalando Certbot para Let's Encrypt..."
apt install -y certbot

# --- Paso 4: Crear estructura de directorios ---
echo ""
echo "[4/5] Creando estructura de directorios..."
mkdir -p /opt/ejbca
mkdir -p /opt/ejbca/nginx/conf.d
mkdir -p /opt/ejbca/nginx/webroot

echo ""
echo "[5/5] Setup completado!"
echo ""
echo "=========================================="
echo "  PRÓXIMOS PASOS:"
echo "=========================================="
echo ""
echo "  1. Copiar archivos del proyecto a /opt/ejbca/"
echo "     - docker-compose.yml"
echo "     - .env (desde .env.example, con contraseñas reales)"
echo "     - nginx/nginx.conf"
echo "     - nginx/conf.d/default.conf"
echo ""
echo "  2. Configurar .env con contraseñas seguras:"
echo "     cd /opt/ejbca"
echo "     cp .env.example .env"
echo "     # Generar contraseñas: openssl rand -base64 24"
echo "     nano .env"
echo ""
echo "  3. Levantar EJBCA:"
echo "     cd /opt/ejbca"
echo "     docker compose up -d"
echo "     docker compose logs -f"
echo ""
echo "  4. Obtener certificado Let's Encrypt:"
echo "     certbot certonly --webroot \\"
echo "       -w /opt/ejbca/nginx/webroot \\"
echo "       -d pki.upeu.edu.pe \\"
echo "       --agree-tos -m admin@upeu.edu.pe"
echo ""
echo "  5. Activar SSL en Nginx:"
echo "     cp nginx/conf.d/default-ssl.conf nginx/conf.d/default.conf"
echo "     docker compose restart nginx"
echo ""
echo "  6. Configurar renovación automática:"
echo "     crontab -e"
echo "     # Agregar: 0 3 * * * certbot renew --quiet --post-hook \"docker restart nginx-proxy\""
echo ""
echo "=========================================="
