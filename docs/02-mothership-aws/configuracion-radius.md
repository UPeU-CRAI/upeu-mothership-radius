# Configuración RADIUS de la Mothership

Configuración central de clients, usuarios, EAP y optimización del servidor FreeRADIUS en AWS.

---

## 1. Definir Satellites como Clientes

Edita `/etc/freeradius/3.0/clients.conf` y añade al final:

```bash
sudo nano /etc/freeradius/3.0/clients.conf
```

```ini
client satellite-lima-01 {
    ipaddr = 190.239.28.70
    secret = upeu_crai_local_2026
    shortname = SAT-LIMA-01
    require_message_authenticator = yes
}
```

---

## 2. Configurar Usuarios de Prueba

Edita `/etc/freeradius/3.0/users` y añade al principio del archivo:

```bash
sudo nano /etc/freeradius/3.0/users
```

```
test1  Cleartext-Password := "2026"
test2  Cleartext-Password := "2026"
```

> [!NOTE]
> Estos usuarios son para pruebas iniciales. En producción, la autenticación se delega a certificados EAP-TLS emitidos por Microsoft Cloud PKI.

---

## 3. Configuración EAP-TLS (Módulo EAP)

El módulo EAP es el corazón de la autenticación por certificados. Abre el archivo:

```bash
sudo nano /etc/freeradius/3.0/mods-available/eap
```

### Cambios principales:

1. **Línea 27** — Cambiar tipo EAP por defecto:
   ```
   default_eap_type = tls
   ```

2. **Sección `tls-config tls-common`** — Reemplazar con bloque optimizado para UPeU:

```ini
tls-config tls-common {
    # --- CERTIFICADOS (Rutas UPeU) ---
    # private_key_password = whatever  # Comentar si la llave no tiene pass
    private_key_file = ${certdir}/upeu/server-key.pem
    certificate_file = ${certdir}/upeu/server-cert.pem
    ca_file = ${certdir}/upeu/ca-root.pem
    ca_path = ${cadir}

    # --- OPTIMIZACIÓN DE RENDIMIENTO ---
    dh_file = ${certdir}/dh
    random_file = /dev/urandom
    fragment_size = 1024    # Vital para certificados grandes de Microsoft
    include_length = yes

    tls_min_version = "1.2"
    tls_max_version = "1.2"  # Se puede subir a 1.3 si los APs lo soportan
    ecdh_curve = "prime256v1"

    # --- CACHÉ Y FAST RECONNECT (Estándar InkBridge) ---
    cache {
        enable = yes
        lifetime = 24           # Horas de vida de la sesión
        max_entries = 255       # Máximo de entradas en caché (0 = infinito)
        name = "EAP_TLS_Cache"
        persist_dir = "${logdir}/tlscache"
    }
}
```

3. **Habilitar recuperación de políticas** — En las secciones `peap` y `ttls`:

```ini
peap {
    ...
    use_tunneled_reply = yes
}

ttls {
    ...
    use_tunneled_reply = yes
}
```

### Generar archivo Diffie-Hellman

```bash
# Generar DH params (tarda 2-5 minutos)
sudo openssl dhparam -out /etc/freeradius/3.0/certs/dh 2048

# Asignar permisos
sudo chown freerad:freerad /etc/freeradius/3.0/certs/dh
```

---

## 4. Optimización de Performance (Thread Pool)

Para manejar picos de inicio de clases, edita `/etc/freeradius/3.0/radiusd.conf`:

```bash
sudo nano /etc/freeradius/3.0/radiusd.conf
```

Busca la sección `thread pool` y ajusta:

```ini
thread pool {
    start_servers = 10
    max_servers = 150           # Aumentado para ráfagas de alumnos
    min_spare_servers = 5
    max_spare_servers = 20
    max_requests_per_server = 1000  # Evita fugas de memoria
}
```

---

## 5. Configuración de Logging

En el mismo archivo `radiusd.conf`, busca la sección `log`:

```ini
log {
    destination = files
    colourise = yes
    file = ${logdir}/radius.log
    syslog_facility = daemon
    stripped_names = no
    auth = yes              # Registrar intentos de login
    auth_badpass = yes      # Registrar contraseñas erróneas
    auth_goodpass = no      # No registrar contraseñas correctas (seguridad)
}
```

> [!TIP]
> En la **Mothership** conviene activar `auth = yes` para auditoría completa. En los **Satellites** puede dejarse en `no` para ahorrar disco, ya que la Mothership centraliza los registros.

---

## 6. Validación y Reinicio

```bash
# Validar configuración
sudo freeradius -CX

# Si no hay errores, reiniciar el servicio
sudo systemctl restart freeradius

# Verificar estado
sudo systemctl status freeradius
```
