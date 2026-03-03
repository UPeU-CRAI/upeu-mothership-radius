# 2. Configuración RADIUS de la Mothership (AWS)

> **Rol:** Servidor RADIUS Master — Cerebro central de autenticación  
> **Referencia:** [InkBridge Networks — RADIUS for Universities](https://www.inkbridgenetworks.com/blog/blog-10/radius-for-universities-122)  
> **Versión:** FreeRADIUS 3.2.x sobre Ubuntu 24.04 LTS (AWS EC2)  

---

## Filosofía: ¿Por Qué EAP-TLS? (Zero Trust)

La UPeU implementa un modelo de **Cero Confianza** para su red Wi-Fi. Esto significa que **ningún dispositivo accede a la red por contraseña** — solo mediante un certificado digital emitido por Microsoft Cloud PKI y distribuido automáticamente por Intune.

```mermaid
flowchart LR
    subgraph zt["🛡️ Zero Trust — Sin Contraseñas"]
        direction TB
        A["❌ PEAP/MSCHAPv2<br/><i>Contraseña viaja por la red</i><br/><i>Vulnerable a ataques de diccionario</i>"]
        B["✅ EAP-TLS<br/><i>Certificado digital x.509</i><br/><i>Imposible de clonar sin llave privada</i>"]
    end

    style A fill:#dc2626,color:#fff,stroke:#991b1b
    style B fill:#059669,color:#fff,stroke:#047857
```

**Decisión de diseño:** Al usar EAP-TLS exclusivamente, eliminamos los vectores de ataque más comunes en redes universitarias:
- **Evil Twin AP:** Inútil sin el certificado de la CA raíz de la UPeU.
- **Credential Stuffing:** No hay credenciales que robar.
- **Man-in-the-Middle:** El handshake TLS mutuo verifica ambos extremos.

---

## Diagrama: Flujo EAP-TLS Interno del Servidor

```mermaid
sequenceDiagram
    participant D as 💻 Dispositivo
    participant AP as 📡 Access Point
    participant S as 🛰️ Satellite
    participant M as 🚀 Mothership
    participant CA as 🔐 Cloud PKI

    Note over D,M: --- Primera Conexión (Full Handshake) ---

    D->>AP: EAP-Response/Identity
    AP->>S: RADIUS Access-Request
    S->>M: Proxy Forward (UDP 1812)
    
    M->>M: Verificar certificado del dispositivo
    M->>M: Validar cadena CA (ca-root.pem)
    M->>M: Verificar CN={{UserEmail}} contra Entra ID
    
    alt Certificado válido
        M->>M: Generar Session Ticket
        M->>M: Guardar en /var/log/freeradius/tlscache
        M-->>S: Access-Accept + VLAN + Session-Ticket
        S-->>AP: Access-Accept
        AP-->>D: ✅ Conectado
    else Certificado inválido o revocado
        M-->>S: Access-Reject
        S-->>AP: Access-Reject
        AP-->>D: ❌ Denegado
    end

    Note over D,M: --- Reconexión Rápida (< 24h) ---

    D->>AP: EAP-Response/Identity
    AP->>S: RADIUS Access-Request
    S->>S: Buscar en caché de atributos (rlm_cache)

    alt Cache HIT (atributos en Satellite)
        S-->>AP: Access-Accept (desde caché local)
        Note over S: ">>> CACHE HIT" en radius.log
    else Cache MISS → Mothership con Session Ticket
        S->>M: Proxy Forward (UDP 1812)
        M->>M: Reanudar sesión TLS (tlscache)
        Note over M: Handshake acelerado por Session Ticket
        M-->>S: Access-Accept + VLAN
        S-->>AP: Access-Accept
    end
```

---

## 1. Registro de Satellites como Clientes RADIUS

Cada Satellite debe estar autorizado explícitamente en la Mothership.

📄 **Archivo:** `/etc/freeradius/3.0/clients.conf`

```bash
sudo nano /etc/freeradius/3.0/clients.conf
```

```ini
# ============================================================================
#  SATELLITE: Lima (SAT-LIMA-01)
#  Descripción: Proxy RADIUS en la sede de Lima. Reenvía peticiones EAP-TLS.
#  Ref: docs/03-satellites-locales/configuracion-proxy.md
# ============================================================================
client satellite-lima-01 {
    ipaddr   = <IP_PUBLICA_SAT_LIMA_01>        # IP pública de la sede Lima
    secret   = <SHARED_SECRET_UPEU>            # Secreto compartido (mín. 16 caracteres)
    shortname = SAT-LIMA-01
    require_message_authenticator = yes        # Mitigación CVE-2024-3596 (BLASTRADIUS)
    limit_proxy_state = yes                    # Previene abuso del atributo Proxy-State
}

# ============================================================================
#  TEMPLATE: Agregar futuros Satellites aquí
# ============================================================================
# client satellite-juliaca-01 {
#     ipaddr   = <IP_PUBLICA_SATELLITE_JULIACA>
#     secret   = <SHARED_SECRET_UPEU>
#     shortname = SAT-JULIACA-01
#     require_message_authenticator = yes
#     limit_proxy_state = yes
# }
```

> [!IMPORTANT]
> **Mitigación BLASTRADIUS (CVE-2024-3596):** Ambos atributos son obligatorios en FreeRADIUS 3.2.x:
> - **`require_message_authenticator = yes`** — Obliga al cliente a incluir el atributo Message-Authenticator en cada paquete, previniendo ataques de inyección de paquetes RADIUS falsificados.
> - **`limit_proxy_state = yes`** — Previene el abuso del atributo Proxy-State para ataques de amplificación. Sin este flag, un atacante con acceso a la red RADIUS podría explotar el servidor como reflector.

---

## 2. Usuarios de Prueba (Solo Desarrollo)

📄 **Archivo:** `/etc/freeradius/3.0/users`

```bash
sudo nano /etc/freeradius/3.0/users
```

```ini
# ============================================================================
#  USUARIOS DE PRUEBA — Solo para validación inicial del túnel Satellite→Mothership
#  ⚠️  ELIMINAR en producción. La autenticación real es por certificado (EAP-TLS).
# ============================================================================
test1  Cleartext-Password := "<TEST_PASSWORD>"
test2  Cleartext-Password := "<TEST_PASSWORD>"
```

> [!CAUTION]
> Estos usuarios **no deben existir en producción**. En el modelo Zero Trust de la UPeU, toda autenticación se realiza mediante certificados x.509 emitidos por Microsoft Cloud PKI. Ver [04-identidad-y-pki/perfiles-intune.md](../04-identidad-y-pki/perfiles-intune.md).

---

## 3. Módulo EAP-TLS — Configuración Completa

Este es el componente central del servidor. Configura la autenticación por certificados, la caché TLS y los métodos EAP habilitados.

> [!CAUTION]
> **Lección aprendida:** NO editar el archivo EAP por defecto de Ubuntu (tiene ~1200 líneas con comentarios). Cualquier directiva duplicada o fuera de lugar rompe la inicialización TLS con el error `TLS Server requires a certificate file`. En su lugar, **reescribir el archivo completo** con la configuración mínima validada.

📄 **Archivo:** `/etc/freeradius/3.0/mods-available/eap`

### 3.1 Elegir tipo de certificados

```mermaid
flowchart TD
    Q{"¿Tienes certificados<br/>de Azure Cloud PKI?"}
    A["✅ Opción A: Producción<br/><i>Certificados de Microsoft Cloud PKI</i>"]
    B["🧪 Opción B: Temporal<br/><i>Certificados autofirmados</i>"]

    Q -->|"Sí"| A
    Q -->|"No (aún)"| B

    style A fill:#059669,color:#fff
    style B fill:#d97706,color:#fff
```

---

### 3.2 Opción B: Certificados temporales (sin Azure Cloud PKI)

> Usar esta opción para **pruebas iniciales** cuando aún no se tienen los certificados de Microsoft Cloud PKI. Cuando los tengas, cambiar a la Opción A.

#### Paso 1: Generar certificado autofirmado sin contraseña

```bash
# Generar llave + certificado autofirmado (válido 1 año)
sudo openssl req -x509 -newkey rsa:2048 \
    -keyout /etc/freeradius/3.0/certs/server-test.key \
    -out /etc/freeradius/3.0/certs/server-test.pem \
    -days 365 -nodes \
    -subj "/CN=MOTHERSHIP-AWS"

# Asignar permisos a FreeRADIUS
sudo chown freerad:freerad /etc/freeradius/3.0/certs/server-test.key
sudo chown freerad:freerad /etc/freeradius/3.0/certs/server-test.pem
sudo chmod 640 /etc/freeradius/3.0/certs/server-test.key
```

#### Paso 2: Generar parámetros Diffie-Hellman

```bash
# Generar parámetros DH (tarda 1-2 minutos)
sudo openssl dhparam -out /etc/freeradius/3.0/certs/dh 2048
sudo chown freerad:freerad /etc/freeradius/3.0/certs/dh
```

#### Paso 3: Respaldar y reemplazar el archivo EAP

```bash
# Respaldar el archivo original
sudo cp /etc/freeradius/3.0/mods-available/eap /etc/freeradius/3.0/mods-available/eap.original.bak

# Escribir configuración limpia
sudo tee /etc/freeradius/3.0/mods-available/eap > /dev/null << 'ENDOFFILE'
eap {
    # Para pruebas con usuario/contraseña usar peap
    # Para producción con certificados cambiar a tls
    default_eap_type = peap
    timer_expire = 60
    ignore_unknown_eap_types = no
    cisco_accounting_username_bug = no
    max_sessions = ${max_requests}

    tls-config tls-common {
        # --- CERTIFICADOS TEMPORALES (autofirmados) ---
        # Cambiar a rutas de Cloud PKI cuando estén disponibles
        private_key_file = /etc/freeradius/3.0/certs/server-test.key
        certificate_file = /etc/freeradius/3.0/certs/server-test.pem
        ca_file = /etc/freeradius/3.0/certs/server-test.pem
        ca_path = /etc/freeradius/3.0/certs
        dh_file = /etc/freeradius/3.0/certs/dh
        random_file = /dev/urandom

        fragment_size = 1024
        include_length = yes

        tls_min_version = "1.2"
        tls_max_version = "1.2"
        cipher_list = "DEFAULT"
        ecdh_curve = "prime256v1"

        cache {
            enable = yes
            lifetime = 24
            name = "EAP_TLS_Cache"
            max_entries = 255
        }
    }

    tls {
        tls = tls-common
    }

    # Sub-módulos EAP requeridos por PEAP y TTLS
    md5 {
    }

    mschapv2 {
    }

    peap {
        tls = tls-common
        default_eap_type = mschapv2
        virtual_server = inner-tunnel
    }

    ttls {
        tls = tls-common
        default_eap_type = md5
        virtual_server = inner-tunnel
    }
}
ENDOFFILE

# Restaurar permisos del archivo
sudo chown freerad:freerad /etc/freeradius/3.0/mods-available/eap
```

#### Paso 4: Validar

```bash
sudo freeradius -CX
# Resultado esperado: "Configuration appears to be OK"
```

#### Paso 5: Habilitar el módulo mschap

PEAP utiliza MSCHAPv2 internamente. El módulo debe estar habilitado:

```bash
# Crear symlink si no existe
sudo ln -sf /etc/freeradius/3.0/mods-available/mschap /etc/freeradius/3.0/mods-enabled/mschap

# Validar y reiniciar
sudo freeradius -CX && sudo systemctl restart freeradius
```

> [!WARNING]
> **Certificados autofirmados = solo para pruebas.** Los dispositivos con Intune no confiarán en estos certificados. Para producción con EAP-TLS real, necesitas los certificados de Microsoft Cloud PKI (Opción A).

---

### 3.3 Opción A: Certificados de producción (Azure Cloud PKI)

> Usar esta opción cuando tengas los certificados descargados de Microsoft Cloud PKI. Ver [cloud-pki-config.md](../04-identidad-y-pki/cloud-pki-config.md) para los pasos de creación y descarga de certificados.

#### Paso 1: Instalar certificados en la Mothership

Seguir los pasos de [cloud-pki-config.md — Paso 3](../04-identidad-y-pki/cloud-pki-config.md#paso-3-desplegar-certificados-en-la-mothership-aws) para transferir e instalar:
- `ca-root.pem` — Root CA
- `ca-issuing.pem` — Issuing CA
- `server-cert.pem` — Certificado del servidor
- `server-key.pem` — Llave privada del servidor
- `ca-chain.pem` — Cadena (Root + Issuing concatenados)

#### Paso 2: Generar parámetros Diffie-Hellman (si no existe)

```bash
sudo openssl dhparam -out /etc/freeradius/3.0/certs/dh 2048
sudo chown freerad:freerad /etc/freeradius/3.0/certs/dh
```

#### Paso 3: Reemplazar el archivo EAP

```bash
sudo cp /etc/freeradius/3.0/mods-available/eap /etc/freeradius/3.0/mods-available/eap.temp.bak

sudo tee /etc/freeradius/3.0/mods-available/eap > /dev/null << 'ENDOFFILE'
eap {
    # Producción: tls (certificados Cloud PKI)
    # Pruebas con usuario/contraseña: peap
    default_eap_type = tls
    timer_expire = 60
    ignore_unknown_eap_types = no
    cisco_accounting_username_bug = no
    max_sessions = ${max_requests}

    tls-config tls-common {
        # --- CERTIFICADOS DE PRODUCCIÓN (Microsoft Cloud PKI) ---
        # Ref: docs/04-identidad-y-pki/cloud-pki-config.md
        #
        # Descomentar si la llave tiene passphrase:
        # private_key_password = <CERT_PASSWORD>
        private_key_file = /etc/freeradius/3.0/certs/upeu/server-key.pem
        certificate_file = /etc/freeradius/3.0/certs/upeu/server-cert.pem
        ca_file = /etc/freeradius/3.0/certs/upeu/ca-chain.pem
        ca_path = /etc/freeradius/3.0/certs
        dh_file = /etc/freeradius/3.0/certs/dh
        random_file = /dev/urandom

        # Verificación CRL (revocar dispositivos robados)
        check_crl = yes

        # Rendimiento para certificados pesados de Cloud PKI
        fragment_size = 1024
        include_length = yes

        # Seguridad TLS
        tls_min_version = "1.2"
        cipher_list = "ECDHE+AESGCM:ECDHE+CHACHA20:!aNULL:!MD5:!DSS"
        ecdh_curve = "prime256v1"

        # Caché TLS + Fast Reconnect
        cache {
            enable = yes
            lifetime = 24
            name = "EAP_TLS_Cache"
            max_entries = 1024
            persist_dir = "/var/log/freeradius/tlscache"

            # Preservar VLANs en reconexiones rápidas
            store {
                &reply:Tunnel-Type
                &reply:Tunnel-Medium-Type
                &reply:Tunnel-Private-Group-ID
                &reply:Reply-Message
            }
        }
    }

    tls {
        tls = tls-common
    }

    # Sub-módulos EAP (requeridos por PEAP y TTLS)
    md5 {
    }

    mschapv2 {
    }

    peap {
        tls = tls-common
        default_eap_type = mschapv2
        virtual_server = inner-tunnel
    }

    ttls {
        tls = tls-common
        default_eap_type = md5
        virtual_server = inner-tunnel
    }
}
ENDOFFILE

sudo chown freerad:freerad /etc/freeradius/3.0/mods-available/eap
```

#### Paso 4: Crear directorio de caché y validar

```bash
# Crear directorio de caché TLS
sudo mkdir -p /var/log/freeradius/tlscache
sudo chown freerad:freerad /var/log/freeradius/tlscache
sudo chmod 700 /var/log/freeradius/tlscache

# Validar configuración
sudo freeradius -CX
# Resultado esperado: "Configuration appears to be OK"
```

> [!IMPORTANT]
> **Antes de arrancar con Opción A**, asegúrate de haber creado `ca-chain.pem`:
> ```bash
> sudo bash -c "cat /etc/freeradius/3.0/certs/upeu/ca-root.pem \
>                    /etc/freeradius/3.0/certs/upeu/ca-issuing.pem \
>               > /etc/freeradius/3.0/certs/upeu/ca-chain.pem"
> sudo chown freerad:freerad /etc/freeradius/3.0/certs/upeu/ca-chain.pem
> ```

---

### 3.4 Migrar de Opción B → Opción A

Cuando obtengas los certificados de Azure Cloud PKI:

| Paso | Acción |
|---|---|
| 1 | Descargar certificados de Cloud PKI → [cloud-pki-config.md](../04-identidad-y-pki/cloud-pki-config.md) |
| 2 | Instalar en `/etc/freeradius/3.0/certs/upeu/` |
| 3 | Crear `ca-chain.pem` (concatenar Root + Issuing) |
| 4 | Reemplazar el archivo EAP con la Opción A (paso 3.3) |
| 5 | Ejecutar `sudo freeradius -CX` para validar |
| 6 | Reiniciar: `sudo systemctl restart freeradius` |

### 3.5 Cached-Session-Policy — Preservar VLANs en Fast Reconnect

Cuando la Mothership reanuda una sesión TLS usando un Session Ticket, FreeRADIUS salta la validación completa del certificado pero debe **restaurar los atributos de política** (VLAN, Reply-Message) para que el AP asigne correctamente la VLAN al alumno.

El bloque `store {}` incluido dentro de `cache {}` en la Opción A es el mecanismo para esto: los atributos `Tunnel-*` se guardan junto con el Session Ticket en `persist_dir` y se restauran automáticamente en cada reconexión rápida.

> [!IMPORTANT]
> **Sin `store {}`**, en una reconexión rápida el dispositivo entra a la red **sin VLAN asignada**, cayendo a la VLAN nativa del switch. Para verificar que funciona, comprobar que los paquetes `Access-Accept` de reconexión en el log de la Mothership incluyen los atributos `Tunnel-Type`, `Tunnel-Medium-Type` y `Tunnel-Private-Group-ID`.

---

## 4. Preparación del Almacén de Caché TLS

La caché TLS necesita un directorio en disco con permisos restrictivos:

```bash
# Directorio principal de caché (sesiones TLS)
sudo mkdir -p /var/log/freeradius/tlscache
sudo chown freerad:freerad /var/log/freeradius/tlscache
sudo chmod 700 /var/log/freeradius/tlscache

```

### Limpieza Automática (Cronjob)

Sin limpieza, la carpeta acumulará miles de archivos. Programar purga nocturna:

```bash
# Abrir editor de crontab
sudo crontab -e

# Agregar al final — limpia archivos con más de 2 días a las 03:00 AM
0 3 * * * find /var/log/freeradius/tlscache -type f -mtime +2 -delete
```

### Verificar que la Caché Funciona

Después de una autenticación exitosa:

```bash
# Contar sesiones almacenadas
sudo ls -1 /var/log/freeradius/tlscache | wc -l

# Ver detalles (archivos hexadecimales = Session Tickets)
sudo ls -la /var/log/freeradius/tlscache
```

> [!TIP]
> Si aparecen archivos hexadecimales, el Fast Reconnect está activo. Los dispositivos que ya se autenticaron **no necesitan un nuevo handshake** aunque reinicies la Mothership.

### Consideraciones Multi-Satellite (Roaming)

```mermaid
flowchart LR
    subgraph local["Caché LOCAL (actual)"]
        S1["🛰️ Satellite 1<br/>Cache propia"]
        S2["🛰️ Satellite 2<br/>Cache propia"]
    end

    subgraph central["Caché CENTRALIZADA (futuro)"]
        R["🗄️ Redis / Memcached"]
        S3["🛰️ Satellite 1"] --> R
        S4["🛰️ Satellite 2"] --> R
    end

    style local fill:#fef3c7,stroke:#d97706
    style central fill:#d1fae5,stroke:#059669
```

> [!IMPORTANT]
> En FreeRADIUS 3.x, la caché TLS es **local por servidor**. Si un alumno cambia de edificio (Satellite 1 → Satellite 2), se forzará un handshake completo. Para roaming real entre campus, implementar **Redis centralizado** como backend de caché compartida.

---

## 5. Optimización de Performance (Thread Pool)

> [!WARNING]
> **Instancia recomendada para producción:** El `t2.micro` (1 vCPU, 1 GB RAM) documentado en [despliegue-instancia.md](despliegue-instancia.md) es suficiente para laboratorio y pruebas, pero **no para producción universitaria**. Con `max_servers = 150` hilos realizando handshakes EAP-TLS (operaciones RSA/ECDSA), se agotarán los créditos de CPU del `t2.micro` en minutos durante el pico de inicio de clases. Para producción con ~5,000 alumnos, se recomienda mínimo **`t3.medium`** (2 vCPU, 4 GB RAM) o superior.

📄 **Archivo:** `/etc/freeradius/3.0/radiusd.conf`

```bash
sudo nano /etc/freeradius/3.0/radiusd.conf
```

### Cálculo para UPeU

| Métrica | Valor | Justificación |
|---|---|---|
| Alumnos activos | ~5,000 | Matrícula estimada en todas las sedes |
| Conexiones simultáneas pico | ~800 | Inicio de clases (08:00 AM) |
| Reconexiones/hora | ~200 | Movimiento entre edificios |
| Threads recomendados | 150 | 800 ÷ 5.3 req/thread + margen 15% |

```ini
thread pool {
    # Hilos iniciales al arrancar (pre-carga para el inicio del día)
    start_servers = 10

    # Máximo de hilos concurrentes — dimensionado para picos de matrícula
    # InkBridge recomienda: (conexiones_pico / 5) + 20% de margen
    max_servers = 150

    # Mínimo de hilos en espera (listos para ráfagas imprevistas)
    # Aumentado a 15 para absorber picos de inicio de clases (08:00 AM)
    min_spare_servers = 15

    # Máximo de hilos ociosos antes de que el servidor los recicle
    max_spare_servers = 20

    # Límite de peticiones por hilo antes de reciclar el thread
    # Previene fugas de memoria en jornadas largas de exámenes
    max_requests_per_server = 1000
}
```

---

## 6. Configuración de Logging (Política de Auditoría)

En el mismo archivo `radiusd.conf`, sección `log`:

```ini
log {
    destination = files
    colourise = yes
    file = ${logdir}/radius.log
    syslog_facility = daemon
    stripped_names = no

    # --- POLÍTICA DE AUDITORÍA (Zero Trust) ---

    # Registrar TODOS los intentos de autenticación (exitosos y fallidos)
    # Obligatorio en la Mothership para auditoría centralizada
    auth = yes

    # Registrar contraseñas erróneas para detectar ataques de fuerza bruta
    # ⚠️  Solo habilitar en la Mothership, nunca en Satellites
    auth_badpass = yes

    # NO registrar contraseñas correctas (principio de mínimo privilegio)
    auth_goodpass = no
}
```

> [!WARNING]
> **Política de Auditoría InkBridge:**
> - **Mothership:** `auth = yes` + `auth_badpass = yes` (registro completo para cumplimiento)
> - **Satellites:** `auth = no` (no duplicar registros; la Mothership ya centraliza la auditoría)

---

## 7. Asignación de VLAN y Accounting (Virtual Server)

📄 **Archivo:** `/etc/freeradius/3.0/sites-available/default`

```bash
sudo nano /etc/freeradius/3.0/sites-available/default
```

### 7.1 VLAN Assignment en `post-auth`

Los atributos RADIUS para VLAN 802.1Q deben enviarse en el `Access-Accept`. Localizar la sección `post-auth {}` y agregar:

```ini
post-auth {
    # ... directivas existentes ...

    # ================================================================
    #  ASIGNACIÓN DE VLAN — Basada en el CN del certificado
    #
    #  Pendiente: integración LDAP con Entra ID para asignación
    #  dinámica según grupo (Alumnos, Docentes, Staff).
    #  Ver: docs/04-identidad-y-pki/microsoft-entra-id.md
    #
    #  Configuración actual: estática por sufijo de dominio.
    #  Reemplazar con política LDAP cuando esté disponible.
    # ================================================================
    if (&TLS-Client-Cert-Subject-Alt-Name-Email =~ /@upeu\.edu\.pe$/) {
        update reply {
            &Tunnel-Type            := VLAN     # Tipo: 802.1Q VLAN (valor 13)
            &Tunnel-Medium-Type     := IEEE-802  # Medio: Ethernet (valor 6)
            &Tunnel-Private-Group-Id := "<VLAN_ID_ALUMNOS>"  # Ej: "100"
        }
    }
}
```

> [!NOTE]
> **Mapeo de VLANs planificado** (pendiente integración LDAP con Entra ID):
> - Grupo `Alumnos` → `Tunnel-Private-Group-Id = "<VLAN_ID_ALUMNOS>"`
> - Grupo `Docentes` → `Tunnel-Private-Group-Id = "<VLAN_ID_DOCENTES>"`
> - Grupo `Staff` → `Tunnel-Private-Group-Id = "<VLAN_ID_STAFF>"`

### 7.2 Accounting en `accounting`

FreeRADIUS procesa los paquetes Accounting-Request (UDP 1813) en la sección `accounting {}`. Agregar el módulo `detail` para registrar sesiones en disco:

```ini
accounting {
    # Registrar paquetes de accounting en archivo de detalle
    # (complementa el radius.log para auditoría de uso de red)
    detail

    # Actualizar la sesión en el log de autenticación
    auth_log

    # ... resto de directivas existentes ...
}
```

> [!TIP]
> Los registros de accounting se almacenan en `/var/log/freeradius/radacct/`. Cada AP crea un subdirectorio con su IP. Útil para auditoría de tiempo de conexión y uso de ancho de banda por usuario.

---

## 8. Validación y Activación

### Pre-vuelo (obligatorio antes de reiniciar)

> [!CAUTION]
> **Opción A (Cloud PKI):** Asegúrate de haber creado `ca-chain.pem` (sección 3.3) antes de reiniciar. Sin ese archivo el servicio fallará al arrancar.
> **Opción B (Temporal):** No requiere `ca-chain.pem` — usa el certificado autofirmado directamente.

```bash
# Verificar que no hay errores de sintaxis en toda la configuración
sudo freeradius -CX
```

Si la salida termina con `Configuration appears to be OK`, proceder:

```bash
# Reiniciar el servicio
sudo systemctl restart freeradius

# Verificar estado
sudo systemctl status freeradius

# Habilitar inicio automático
sudo systemctl enable freeradius
```

### Test de Autenticación (desde un Satellite)

```bash
# Desde la terminal del Satellite, usando un usuario de prueba
radtest test1 <TEST_PASSWORD> <IP_ELASTICA_MOTHERSHIP> 0 <SHARED_SECRET_UPEU>
```

**Resultado esperado:** `Access-Accept` con atributos de sesión.

---

## Archivos Modificados — Resumen

| Archivo | Cambio Principal |
|---|---|
| `/etc/freeradius/3.0/clients.conf` | Registro de Satellites con BLASTRADIUS mitigation |
| `/etc/freeradius/3.0/users` | Usuarios de prueba (eliminar en producción) |
| `/etc/freeradius/3.0/mods-available/eap` | EAP-TLS + caché TLS + Session Tickets + `check_crl` |
| `/etc/freeradius/3.0/certs/upeu/ca-chain.pem` | Cadena Root CA + Issuing CA (crear con `cat`) |
| `/etc/freeradius/3.0/radiusd.conf` | Thread pool + logging de auditoría |
| `/etc/freeradius/3.0/sites-available/default` | VLAN assignment + accounting |
| `/var/log/freeradius/tlscache/` | Directorio de persistencia de Session Tickets |
| `crontab (root)` | Limpieza nocturna de caché |

---

→ **Siguiente paso:** [Cloud PKI — Configuración de Certificados](../04-identidad-y-pki/cloud-pki-config.md) — instalar los certificados Root CA e Issuing CA referenciados en la config EAP.
