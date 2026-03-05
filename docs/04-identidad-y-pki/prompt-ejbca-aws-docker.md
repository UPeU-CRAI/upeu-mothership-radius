
### CONTEXTO DEL PROYECTO

**Organización:** Universidad Peruana Unión (UPeU) — área CRAI (Centro de Recursos para el Aprendizaje y la Investigación).

**Proyecto:** Infraestructura de autenticación de red 802.1X para el campus universitario, usando FreeRADIUS (arquitectura Mothership/Satellites) con autenticación EAP-TLS basada en certificados digitales.

**Repositorio del proyecto:** https://github.com/orgs/UPeU-CRAI/projects

**Escala objetivo:**
- ~15,000 usuarios, cada uno con 2-3 dispositivos (30,000 - 45,000 certificados potenciales)
- Arranque en fase piloto con 50 dispositivos de prueba
- Crecimiento progresivo: 50 → 5,000 → 45,000 → escala completa

---

### DECISIONES YA TOMADAS

1. **PKI:** EJBCA Community Edition (descartamos Azure Cloud PKI por costo, y step-ca porque su versión open source no soporta Dynamic SCEP para Intune).

2. **Método de instalación:** Docker Hub (imagen oficial `keyfactor/ejbca-ce`), NO desde código fuente de GitHub ni desde AWS Marketplace.

3. **Base de datos:** PostgreSQL 16 (los drivers JDBC vienen incluidos en el contenedor de EJBCA). Descartamos MariaDB y H2.

4. **Infraestructura:** AWS EC2 en región `us-east-1` (Virginia). La cuenta AWS ya existe ("AWS UPeU").

5. **Disponibilidad:** 24/7 (producción continua).

6. **Licenciamiento Microsoft:** Microsoft 365 A3/A5 Education (incluye Intune Plan 1 y Entra ID P1/P2). NO necesitamos Azure Cloud PKI ni Intune Suite — todo lo que necesitamos para SCEP con CA de terceros ya está incluido.

7. **Dominio:** Se usará `pki.upeu.edu.pe`. El equipo de infraestructura de UPeU creará un registro DNS tipo A apuntando a la Elastic IP de AWS.

8. **HTTPS:** Let's Encrypt + Certbot + Nginx como reverse proxy (gratuito, renovación automática).

---

### ARQUITECTURA OBJETIVO

```
Internet (HTTPS :443)
    → Nginx (Let's Encrypt TLS para pki.upeu.edu.pe)
        → EJBCA CE container (Docker)
            ├── Puerto 8080: HTTP interno (SCEP, CRL, OCSP)
            ├── Puerto 8443: Admin UI (acceso restringido)
            └── Volúmenes persistentes (DB, claves, certificados)

Docker Compose levanta 3 servicios:
    ├── postgres:16-alpine  (base de datos)
    ├── keyfactor/ejbca-ce  (autoridad certificadora)
    └── nginx:alpine        (reverse proxy + TLS)

Security Group AWS:
    ├── Puerto 22   → SSH (solo tu IP)
    ├── Puerto 80   → HTTP (para challenge Let's Encrypt, redirige a 443)
    ├── Puerto 443  → HTTPS/SCEP desde internet (para Intune)
    └── Puerto 8443 → Admin UI (solo IP del administrador / VPN)
```

---

### ARCHIVOS DE CONFIGURACIÓN YA PREPARADOS

A continuación los archivos que ya tengo listos. Úsalos como base y ajústalos si es necesario durante la guía.

#### Estructura de archivos:
```
/opt/ejbca/
├── docker-compose.yml
├── .env
├── setup.sh
└── nginx/
    ├── nginx.conf
    ├── webroot/          (vacío, para challenge Certbot)
    └── conf.d/
        ├── default.conf      (config inicial HTTP, antes de Let's Encrypt)
        └── default-ssl.conf  (config producción HTTPS, después de Certbot)
```

---

#### docker-compose.yml

```yaml
networks:
  backend:
    driver: bridge
  frontend:
    driver: bridge

volumes:
  postgres-data:
    driver: local
  ejbca-data:
    driver: local

services:

  ejbca-database:
    container_name: ejbca-database
    image: postgres:16-alpine
    restart: unless-stopped
    networks:
      - backend
    environment:
      - POSTGRES_DB=${DB_NAME}
      - POSTGRES_USER=${DB_USER}
      - POSTGRES_PASSWORD=${DB_PASSWORD}
    volumes:
      - postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER} -d ${DB_NAME}"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

  ejbca-node1:
    hostname: ${EJBCA_HOSTNAME}
    container_name: ejbca
    image: keyfactor/ejbca-ce:latest
    restart: unless-stopped
    depends_on:
      ejbca-database:
        condition: service_healthy
    networks:
      - backend
      - frontend
    environment:
      - DATABASE_JDBC_URL=jdbc:postgresql://ejbca-database:5432/${DB_NAME}
      - DATABASE_USER=${DB_USER}
      - DATABASE_PASSWORD=${DB_PASSWORD}
      - LOG_LEVEL_APP=INFO
      - LOG_LEVEL_SERVER=INFO
      - TLS_SETUP_ENABLED=${TLS_SETUP_MODE:-simple}
    ports:
      - "127.0.0.1:8080:8080"
      - "127.0.0.1:8443:8443"
    volumes:
      - ejbca-data:/opt/keyfactor/appserver/standalone/data

  nginx:
    container_name: nginx-proxy
    image: nginx:alpine
    restart: unless-stopped
    depends_on:
      - ejbca-node1
    networks:
      - frontend
    ports:
      - "0.0.0.0:80:80"
      - "0.0.0.0:443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
      - ./nginx/webroot:/var/www/certbot:ro
```

---

#### .env

```env
# --- Base de Datos PostgreSQL ---
DB_NAME=ejbca
DB_USER=ejbca
DB_PASSWORD=CAMBIAR_password_ejbca_seguro_aqui

# --- EJBCA ---
EJBCA_HOSTNAME=pki.upeu.edu.pe

# Modo TLS:
#   "simple"  = sin certificado cliente (para setup inicial)
#   "true"    = requiere certificado cliente (producción)
TLS_SETUP_MODE=simple
```

---

#### nginx/nginx.conf

```nginx
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;
    sendfile on;
    keepalive_timeout 65;
    client_max_body_size 10M;

    include /etc/nginx/conf.d/*.conf;
}
```

---

#### nginx/conf.d/default.conf (config INICIAL — antes de Let's Encrypt)

```nginx
server {
    listen 80;
    server_name pki.upeu.edu.pe;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location /ejbca/publicweb/ {
        proxy_pass http://ejbca-node1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

---

#### nginx/conf.d/default-ssl.conf (config PRODUCCIÓN — después de Certbot)

```nginx
server {
    listen 80;
    server_name pki.upeu.edu.pe;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name pki.upeu.edu.pe;

    ssl_certificate     /etc/letsencrypt/live/pki.upeu.edu.pe/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/pki.upeu.edu.pe/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;

    add_header Strict-Transport-Security "max-age=63072000" always;
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;

    # SCEP endpoint (Intune solicita certificados aquí)
    location /ejbca/publicweb/apply/scep {
        proxy_pass http://ejbca-node1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 120s;
        proxy_send_timeout 120s;
    }

    # CRL distribution (FreeRADIUS consulta aquí para revocación)
    location /ejbca/publicweb/webdist/ {
        proxy_pass http://ejbca-node1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }

    # OCSP responder
    location /ejbca/publicweb/status/ocsp {
        proxy_pass http://ejbca-node1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }

    # Bloquear todo lo demás (admin UI NO accesible desde internet)
    location / {
        return 403;
    }
}
```

---

### CERTIFICADOS QUE NECESITO EMITIR DESDE EJBCA

1. **Root CA** (1) — Ancla de confianza. Se genera una vez y se resguarda.
2. **Issuing CA / CA Subordinada** (1) — La que emite los certificados día a día. Firmada por la Root CA.
3. **Certificados de servidor RADIUS** (1 por cada servidor FreeRADIUS) — Se configuran en el bloque `tls-config tls-common` de FreeRADIUS como `server.pem` y `server.key`.
4. **Certificados de cliente** (1 por dispositivo) — Se despliegan a los equipos vía Intune/SCEP. Cada dispositivo los presenta al conectarse a Wi-Fi 802.1X con EAP-TLS.

---

### INTEGRACIONES REQUERIDAS

**EJBCA ↔ Microsoft Intune (SCEP):**
- Intune envía solicitudes SCEP al endpoint de EJBCA para emitir certificados de cliente automáticamente.
- Requiere registrar una App en Entra ID con permisos delegados para validar challenges SCEP.
- Usar la API abierta de Microsoft para integración de CAs de terceros con Intune: https://github.com/Microsoft/Intune-Resource-Access
- Crear perfiles en Intune: Trusted Certificate (para distribuir Root CA e Issuing CA) y SCEP Certificate (apuntando a la URL SCEP de EJBCA).

**EJBCA ↔ FreeRADIUS:**
- FreeRADIUS valida los certificados de cliente contra la CA de EJBCA.
- FreeRADIUS usa su propio certificado de servidor emitido por EJBCA.
- Se necesita acceso a CRL y/o OCSP de EJBCA para verificar revocación.

---

### DIMENSIONAMIENTO DE LA INSTANCIA AWS

**Fase 1 — Piloto (50 dispositivos):**
- Instancia: `t3.medium` (2 vCPU, 4 GB RAM)
- Almacenamiento: 30 GB EBS gp3
- Costo estimado: ~$33/mes

**Fase 2 — Producción inicial (2,000-5,000 dispositivos):**
- Instancia: `t3.large` (2 vCPU, 8 GB RAM)
- Almacenamiento: 50 GB EBS gp3
- Costo estimado: ~$66/mes

**Fase 3 — Producción completa (30,000-45,000 dispositivos):**
- Instancia: `m5.large` (2 vCPU, 8 GB RAM, CPU dedicada)
- Almacenamiento: 100 GB EBS gp3
- Costo estimado: ~$69/mes (con Reserved Instance 1 año)

---

### PASOS QUE NECESITO QUE ME GUÍES

#### FASE A — Infraestructura AWS

1. **Lanzar EC2:**
   - t3.medium, Ubuntu 24.04, us-east-1
   - Security Group: SSH (22, mi IP), HTTP (80, 0.0.0.0/0), HTTPS (443, 0.0.0.0/0)
   - Asignar Elastic IP

2. **Preparar el servidor:**
   - Actualizar sistema
   - Instalar Docker Engine + Docker Compose plugin
   - Instalar Certbot
   - Crear estructura de directorios en /opt/ejbca/

3. **Configurar DNS:**
   - Ya tengo la Elastic IP
   - El equipo de UPeU creará registro A: `pki.upeu.edu.pe → <Elastic IP>`
   - Verificar propagación con: `dig pki.upeu.edu.pe A`

#### FASE B — Despliegue EJBCA

4. **Copiar archivos de configuración** a /opt/ejbca/ (los que están arriba)

5. **Configurar .env** con contraseñas seguras (generar con `openssl rand -base64 24`)

6. **Levantar servicios:** `docker compose up -d`

7. **Verificar logs:** `docker compose logs -f` — esperar hasta ver la URL de acceso

#### FASE C — Certificado HTTPS

8. **Obtener certificado Let's Encrypt:**
   ```bash
   certbot certonly --webroot \
     -w /opt/ejbca/nginx/webroot \
     -d pki.upeu.edu.pe \
     --agree-tos -m admin@upeu.edu.pe
   ```

9. **Activar SSL en Nginx:**
   ```bash
   cp nginx/conf.d/default-ssl.conf nginx/conf.d/default.conf
   docker compose restart nginx
   ```

10. **Configurar renovación automática:**
    ```bash
    # En crontab:
    0 3 * * * certbot renew --quiet --post-hook "docker restart nginx-proxy"
    ```

#### FASE D — Configuración de EJBCA (post-instalación)

11. **Acceder a EJBCA Admin UI:**
    - Desde la EC2 o por SSH tunnel: `https://localhost:8443/ejbca/adminweb/`
    - Aceptar el certificado autofirmado

12. **Crear SuperAdmin** (seguir procedimiento oficial de Keyfactor):
    - Ir a RA Web → Make New Request
    - Certificate subtype: ENDUSER
    - Key-pair generation: By the CA
    - Key algorithm: RSA 2048 bits
    - Common Name: SuperAdmin
    - Descargar PKCS#12

13. **Importar certificado SuperAdmin** en el navegador (Firefox recomendado)

14. **Restringir acceso:**
    - Roles and Access Rules → Eliminar "Public Access Role"
    - Super Administrator Role → Members → Agregar SuperAdmin (X509:CN = SuperAdmin, CA = Management CA)
    - Eliminar PublicAccessAuthenticationToken

15. **Cambiar a modo TLS autenticado:**
    - Editar .env: `TLS_SETUP_MODE=true`
    - `docker compose up -d` (recrear contenedor EJBCA)

#### FASE E — Jerarquía PKI

16. **Crear Root CA** en EJBCA
17. **Crear Issuing CA** (subordinada, firmada por Root)
18. **Crear Certificate Profiles:** servidor RADIUS + cliente (dispositivo)
19. **Crear End Entity Profiles**
20. **Habilitar y configurar servicio SCEP**

#### FASE F — Integración con Intune

21. **Registrar App en Entra ID** con permisos para validación SCEP
22. **Configurar API de integración** (Microsoft Intune SCEP third-party CA)
23. **Crear perfil Trusted Certificate** en Intune (Root CA + Issuing CA)
24. **Crear perfil SCEP Certificate** en Intune → URL: `https://pki.upeu.edu.pe/ejbca/publicweb/apply/scep`

#### FASE G — Certificados para FreeRADIUS

25. **Emitir certificado de servidor** para Mothership
26. **Emitir certificados de servidor** para cada Satellite
27. **Exportar en formato PEM** para FreeRADIUS

#### FASE H — Backups y mantenimiento

28. **Backups:** Script de backup de volúmenes Docker + EBS Snapshots automáticos
29. **Actualizaciones:** Procedimiento para actualizar contenedor EJBCA
30. **Monitoreo:** CloudWatch básico

#### FASE I — Pruebas de validación

31. **Verificar SCEP** responde en `https://pki.upeu.edu.pe/ejbca/publicweb/apply/scep`
32. **Probar emisión** de certificado desde Intune a dispositivo de prueba
33. **Verificar FreeRADIUS** valida el certificado de cliente correctamente
34. **Probar revocación** y verificar CRL/OCSP

---

### CONSIDERACIONES IMPORTANTES

- **Docker en producción es válido** para este caso de uso, siempre que se usen volúmenes persistentes, restart policies, y backups.
- **No confundir certificados:** El certificado Let's Encrypt es para HTTPS del servidor web (Nginx). Los certificados de EJBCA son la PKI privada para autenticación 802.1X. Son mundos separados que conviven en el mismo servidor.
- **El endpoint SCEP debe ser HTTPS** y accesible desde internet para que los dispositivos gestionados por Intune puedan solicitar certificados.
- **La UI de administración de EJBCA (8443) NO debe exponerse a internet** — solo acceso desde IPs autorizadas, SSH tunnel, o VPN.
- **EJBCA CE incluye SCEP, CMP y REST API** en la Community Edition. NO necesitamos Enterprise para nuestro caso de uso.
- **FreeRADIUS serie 3.2.x** es la versión que usamos (rama LTS activa). Las rutas de configuración siguen siendo `/etc/freeradius/3.0/` por compatibilidad histórica de paquetes.
- **PostgreSQL** fue elegido sobre MariaDB por mejor soporte en AWS RDS si algún día necesitamos migrar.
- **Referencia oficial de Keyfactor para Docker Compose:** https://docs.keyfactor.com/how-to/latest/start-out-with-ejbca-docker-container (nuestro compose está basado en este tutorial pero adaptado para producción con PostgreSQL, Nginx, healthchecks, y puertos restringidos).

---

### FORMATO DE RESPUESTA ESPERADO

Dame instrucciones paso a paso con los comandos exactos que debo ejecutar. Incluye:
- Comandos de terminal (bash)
- Configuraciones de EJBCA (indica pasos en la UI web cuando sea necesario)
- Explicación breve del "por qué" detrás de cada paso importante
- Warnings sobre errores comunes y cómo evitarlos

Empieza por la Fase A (Infraestructura AWS) y avanza secuencialmente. Si alguna fase es muy larga, podemos dividirla en partes.

## FIN DEL PROMPT
