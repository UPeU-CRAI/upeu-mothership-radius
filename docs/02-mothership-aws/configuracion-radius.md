# Configuración RADIUS de la Mothership (AWS)

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
    ipaddr   = <IP_PUBLICA_SATELLITE_LIMA>     # IP pública de la sede Lima
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

## 3. Módulo EAP-TLS con Persistencia de Caché Integrada

Este es el componente central del servidor. Integra la autenticación por certificados, la caché TLS para Fast Reconnect y los Session Tickets para persistencia en disco.

📄 **Archivo:** `/etc/freeradius/3.0/mods-available/eap`

```bash
sudo nano /etc/freeradius/3.0/mods-available/eap
```

### 3.1 Tipo EAP por defecto

Cambiar la **línea 27** del archivo:

```ini
# Antes:  default_eap_type = md5
# Después: Forzar EAP-TLS exclusivamente (Zero Trust — sin contraseñas)
default_eap_type = tls
```

### 3.2 Bloque `tls-config tls-common` — Configuración Completa

Buscar la sección `tls-config tls-common { ... }` (aprox. línea 300) y reemplazar completamente:

```ini
tls-config tls-common {

    # ================================================================
    #  CERTIFICADOS — Rutas de la PKI de Microsoft Cloud (UPeU)
    #  Ref: docs/04-identidad-y-pki/cloud-pki-config.md
    # ================================================================

    # Llave privada del servidor RADIUS
    # (Generada al configurar el certificado del servidor)
    # private_key_password = <CERT_PASSWORD>   # Descomentar si la llave tiene passphrase
    private_key_file = ${certdir}/upeu/server-key.pem

    # Certificado público del servidor RADIUS
    certificate_file = ${certdir}/upeu/server-cert.pem

    # Cadena de confianza completa — Root CA + Issuing CA concatenadas.
    # La PKI de Microsoft Cloud PKI es de DOS niveles: Root CA → Issuing CA → Certs.
    # FreeRADIUS necesita ambas CAs para validar los certificados de cliente.
    # Crear el archivo de cadena UNA vez (antes de arrancar el servicio):
    #   sudo bash -c "cat ${certdir}/upeu/ca-root.pem ${certdir}/upeu/ca-issuing.pem \
    #                 > ${certdir}/upeu/ca-chain.pem"
    #   sudo chown freerad:freerad ${certdir}/upeu/ca-chain.pem
    #   sudo chmod 640 ${certdir}/upeu/ca-chain.pem
    ca_file = ${certdir}/upeu/ca-chain.pem
    ca_path = ${cadir}

    # Verificación de revocación de certificados — esencial para Zero Trust.
    # Si un dispositivo es robado y su cert se revoca en Microsoft Cloud PKI,
    # FreeRADIUS descargará la CRL (URL en cloud-pki-config.md) y rechazará el cert.
    # ⚠️  Requiere que la Mothership tenga acceso HTTPS saliente a:
    #     https://pkicrl.manage.microsoft.com/crl/<TENANT_ID>/...
    check_crl = yes

    # ================================================================
    #  RENDIMIENTO — Optimización para certificados de Microsoft
    #  InkBridge recomienda fragment_size ≥ 1024 para certificados
    #  pesados de Cloud PKI que incluyen extensiones SCEP
    # ================================================================

    # Parámetros Diffie-Hellman (pre-generados)
    dh_file = ${certdir}/dh

    # Fuente de entropía para operaciones criptográficas
    random_file = /dev/urandom

    # Fragmentación de certificados — Crítico para dispositivos móviles
    # Los certificados de Microsoft Cloud PKI son más grandes que los
    # de una CA on-premise. Sin este valor, muchos dispositivos
    # Android/iOS fallan en el handshake.
    fragment_size = 1024
    include_length = yes

    # ================================================================
    #  SEGURIDAD TLS — Protocolo y curvas criptográficas
    # ================================================================

    # TLS 1.2 mínimo; TLS 1.3 habilitado para clientes modernos
    # (Windows 11, macOS 13+, iOS 16+, Android 10+).
    # No se define tls_max_version para permitir TLS 1.3 automáticamente.
    tls_min_version = "1.2"

    # Suite de cifrado — solo ECDHE con Perfect Forward Secrecy.
    # Excluye cifrados anónimos (!aNULL), MD5 obsoleto (!MD5) y DSS (!DSS).
    cipher_list = "ECDHE+AESGCM:ECDHE+CHACHA20:!aNULL:!MD5:!DSS"

    # Curva elíptica recomendada por Microsoft y compatibles con
    # Windows 11, macOS y dispositivos móviles modernos.
    # Dejarla vacía causa errores en clientes Windows 11.
    ecdh_curve = "prime256v1"

    # ================================================================
    #  CACHÉ TLS + FAST RECONNECT — Estándar InkBridge
    #
    #  Objetivo: "Baja Latencia" — después del primer handshake
    #  exitoso, las reconexiones dentro de 24h no viajan a AWS.
    #  El Session Ticket se almacena en disco (persist_dir) para
    #  sobrevivir reinicios del servicio.
    #
    #  Diagrama de decisión:
    #    Dispositivo se conecta → ¿Existe Session Ticket?
    #      SÍ → Access-Accept inmediato (sin EAP-TLS completo)
    #      NO → Full handshake → Validar cert → Generar ticket
    # ================================================================
    cache {
        # Habilitar caché de sesiones TLS
        enable = yes

        # Tiempo de vida de cada sesión en caché (horas)
        # 24h cubre una jornada académica completa
        lifetime = 24

        # Cantidad máxima de sesiones en memoria
        # Ajustar según población estudiantil activa
        # Para ~5,000 alumnos, 1024 cubre una jornada completa con margen
        max_entries = 1024

        # Nombre interno del almacén de caché
        # Obligatorio cuando se usa persist_dir
        name = "EAP_TLS_Cache"

        # Persistencia en disco — Las sesiones sobreviven un reinicio
        # del servicio FreeRADIUS (ej: durante actualizaciones del SO)
        persist_dir = "${logdir}/tlscache"

        # Cached-Session-Policy: atributos restaurados en Fast Reconnect.
        # Sin este bloque, una reconexión por Session Ticket no recupera
        # la VLAN asignada y el dispositivo entra a la VLAN nativa del switch
        # en lugar de su VLAN de grupo (Alumnos/Docentes/Staff).
        store {
            &reply:Tunnel-Type               # Tipo de túnel VLAN (valor: 13)
            &reply:Tunnel-Medium-Type        # Medio del túnel (valor: 6 = IEEE 802)
            &reply:Tunnel-Private-Group-ID   # Número de VLAN asignado (ej: "100")
            &reply:Reply-Message             # Mensaje de bienvenida (opcional)
        }
    }
}
```

### 3.3 Cached-Session-Policy — Preservar VLANs en Fast Reconnect

Cuando la Mothership reanuda una sesión TLS usando un Session Ticket, FreeRADIUS salta la validación completa del certificado pero debe **restaurar los atributos de política** (VLAN, Reply-Message) para que el AP asigne correctamente la VLAN al alumno.

El bloque `store {}` ya incluido dentro de `cache {}` en la sección 3.2 es el mecanismo para esto: los atributos `Tunnel-*` listados se guardan junto con el Session Ticket en `persist_dir` y se restauran automáticamente en cada reconexión rápida.

> [!IMPORTANT]
> **Sin `store {}`**, en una reconexión rápida el dispositivo entra a la red **sin VLAN asignada**, cayendo a la VLAN nativa del switch. Para verificar que funciona, comprobar que los paquetes `Access-Accept` de reconexión en el log de la Mothership incluyen los atributos `Tunnel-Type`, `Tunnel-Medium-Type` y `Tunnel-Private-Group-ID`.

### 3.4 Generar Parámetros Diffie-Hellman

El archivo DH es requerido por la directiva `dh_file`. Se genera una sola vez:

```bash
# Generar parámetros DH de 2048 bits (tarda 2-5 minutos)
sudo openssl dhparam -out /etc/freeradius/3.0/certs/dh 2048

# Asignar propiedad al usuario del servicio
sudo chown freerad:freerad /etc/freeradius/3.0/certs/dh
```

---

## 4. Preparación del Almacén de Caché TLS

La caché TLS necesita un directorio en disco con permisos restrictivos:

```bash
# Directorio principal de caché (sesiones TLS)
sudo mkdir -p /var/log/freeradius/tlscache
sudo chown freerad:freerad /var/log/freeradius/tlscache
sudo chmod 700 /var/log/freeradius/tlscache

# Directorio de Session Tickets (persistencia entre reinicios)
sudo mkdir -p /var/log/freeradius/tickets
sudo chown freerad:freerad /var/log/freeradius/tickets
sudo chmod 700 /var/log/freeradius/tickets
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
> Asegúrate de haber creado `ca-chain.pem` (sección 3.2) antes de reiniciar. Sin ese archivo el servicio fallará al arrancar.

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
