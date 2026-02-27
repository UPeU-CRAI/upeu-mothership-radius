# Configurar freeRadios de Lima como Satellite

Vamos a convertir tu servidor `vmware01` (`172.16.79.129`) en el brazo derecho del Master de AWS para la sede de Lima.

Dado que en el Master de AWS ya definiste que el cliente de Lima usa el secreto upeu_crai_local_2026, el esclavo debe usar esa misma llave para identificarse ante el jefe.

Sigue estos pasos en tu servidor local:

---

1. **Definir la Mothership como destino**:
Edita `/etc/freeradius/3.0/proxy.conf`. Crea el servidor de AWS y el pool:Plaintext
    
    ```bash
    sudo nano /etc/freeradius/3.0/proxy.conf
    ```
    
    ```bash
    ######################################################################
    #  Definir el servidor Master de AWS
    ######################################################################
    home_server upeu-aws-mothership {
        type = auth+acct
        ipaddr = 54.166.108.154  # IP de tu servidor AWS
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
    
    # Realm por defecto (para cuando el dispositivo no envía dominio)
    realm LOCAL {
        auth_pool = upeu-pool-cloud-auth
        acct_pool = upeu-pool-cloud-auth
    }
    
    realm NULL {
        auth_pool = upeu-pool-cloud-auth
        acct_pool = upeu-pool-cloud-auth
    }
    ```
    
2. **Permitir a los Access Points locales**:
Edita `/etc/freeradius/3.0/clients.conf` en Lima:Plaintext
    
    ```bash
    sudo nano /etc/freeradius/3.0/clients.conf
    ```
    
    ```bash
    #######################################################################
    #  Rango general para todos los APs del campus Lima
    #######################################################################
    client ap-lima-01 {
        ipaddr = 172.16.79.0/24
        secret = upeu_crai_local_2026
        shortname = AP-LIMA-01
    }
    ```
    

> **Nota:** `upeu_crai_local_2026` es la clave que pondrás en la configuración RADIUS de tus Access Points (Ubiquiti, Cisco, etc.).
> 

---

### 3. Prueba de Conexión Esclavo ➔ Master

Para verificar que el esclavo puede hablar con el Master, vamos a detener el servicio y lanzarlo en modo debug (igual que hicimos en AWS):

**Detén el servicio:** 

```bash
sudo systemctl stop freeradius
```

**Lanza el debug:** 

```bash
sudo freeradius -X
```

- **⚠️ Si sale error por algún proceso que no se ha detenido y esta usando el puerto usar esto:**
    
    **1. Fuerza el cierre de cualquier proceso de RADIUS:**
    Ejecuta este comando para "matar" cualquier proceso que esté usando los puertos de FreeRADIUS:
    
    Bash
    
    ```bash
    sudo pkill -9 freeradius
    ```
    
    *(Si te dice que no encontró nada, no te preocupes, es solo para asegurar).*
    
    **2. Verifica que no haya nadie escuchando en esos puertos:**
    
    Bash
    
    ```bash
    sudo ss -lupn | grep 1812
    ```
    
    Si el comando no devuelve nada, los puertos están libres.
    
    **3. Intenta de nuevo el modo debug:**
    
    Bash
    
    ```bash
    sudo freeradius -X
    ```
    

Ahora, **mientras el esclavo está en modo debug**, abre otra terminal en ese mismo servidor esclavo y haz una prueba local:

Bash

```bash
radtest upeu-test-user prueba 127.0.0.1 0 testing123
```

### ¿Qué deberías ver?

- **En el Esclavo (`vmware01`):** Verás que recibe la petición y dice: *"Forwarding request to home server aws_master_lima"*.
- **En el Master (AWS):** Debería aparecer la ráfaga de texto indicando que recibió un paquete desde la IP de tu campus.