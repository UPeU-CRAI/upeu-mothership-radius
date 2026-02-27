# Configuración del Proxy (Satellite Lima)

Configurar el servidor `vmware01` como proxy RADIUS que reenvía peticiones a la Mothership en AWS.

---

## 1. Configurar la Mothership como Destino

Edita `/etc/freeradius/3.0/proxy.conf`:

```bash
sudo nano /etc/freeradius/3.0/proxy.conf
```

Agrega la siguiente configuración:

```ini
######################################################################
#  Definir el servidor Master de AWS
######################################################################
home_server upeu-aws-mothership {
    type = auth+acct
    ipaddr = 54.166.108.154  # Elastic IP de la Mothership en AWS
    port = 1812
    secret = upeu_crai_local_2026
}

######################################################################
#  Pool para balanceo de servidores o failover futuro
######################################################################
home_server_pool upeu-pool-cloud-auth {
    type = fail-over
    home_server = upeu-aws-mothership
}

######################################################################
#  Redireccionar peticiones al pool
######################################################################
# Realm para usuarios con dominio @upeu.edu.pe
realm upeu.edu.pe {
    auth_pool = upeu-pool-cloud-auth
    acct_pool = upeu-pool-cloud-auth
}

# Realm por defecto (cuando el dispositivo no envía dominio)
realm LOCAL {
    auth_pool = upeu-pool-cloud-auth
    acct_pool = upeu-pool-cloud-auth
}

realm NULL {
    auth_pool = upeu-pool-cloud-auth
    acct_pool = upeu-pool-cloud-auth
}
```

---

## 2. Permitir Access Points Locales

Edita `/etc/freeradius/3.0/clients.conf`:

```bash
sudo nano /etc/freeradius/3.0/clients.conf
```

```ini
#######################################################################
#  Rango general para todos los APs del campus Lima
#######################################################################
client ap-lima-01 {
    ipaddr = 172.16.79.0/24
    secret = upeu_crai_local_2026
    shortname = AP-LIMA-01
}
```

> [!NOTE]
> `upeu_crai_local_2026` es la clave que debes configurar en los Access Points (Ubiquiti, Cisco, etc.) como el *RADIUS shared secret*.

---

## 3. Configurar Caché Local para Hits

Para visualizar reconexiones desde caché en los logs, edita el archivo:

```bash
sudo nano /etc/freeradius/3.0/sites-enabled/default
```

Busca la sección `authorize` y agrega el bloque de caché:

```ini
cache
if (ok) {
    # Mensaje visible en el log de Auth
    update reply {
        &Reply-Message += ">>> CACHE HIT: Usuario %{User-Name} autenticado desde memoria local en Lima"
    }
    update control {
        Auth-Type := Accept
    }
}
```

---

## 4. Prueba de Conexión Satellite → Mothership

### Preparar el modo debug

```bash
# Detener servicio
sudo systemctl stop freeradius

# Lanzar en modo debug
sudo freeradius -X
```

### Ejecutar prueba (en otra terminal del Satellite)

```bash
radtest upeu-test-user prueba 127.0.0.1 0 testing123
```

### ¿Qué deberías ver?

| Servidor | Mensaje esperado |
|---|---|
| **Satellite (vmware01)** | `Forwarding request to home server aws_master_lima` |
| **Mothership (AWS)** | Ráfaga de texto indicando que recibió un paquete desde la IP del campus |

---

## 5. Validación Final y Activación

```bash
# Validar configuración
sudo freeradius -CX

# Si todo está OK, activar como servicio
sudo systemctl start freeradius
sudo systemctl enable freeradius

# Verificar estado
sudo systemctl status freeradius
```

> [!WARNING]
> Si después de activar el servicio el Wi-Fi deja de funcionar, revisa los permisos. El modo debug (`-X`) corre como `root` y puede crear archivos que el servicio estándar no puede leer:
> ```bash
> sudo chown -R freerad:freerad /etc/freeradius/3.0/
> ```
