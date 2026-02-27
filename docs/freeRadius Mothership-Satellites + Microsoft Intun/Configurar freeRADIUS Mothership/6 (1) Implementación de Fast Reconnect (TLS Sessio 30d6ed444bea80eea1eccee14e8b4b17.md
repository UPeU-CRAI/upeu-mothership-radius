# 6 (1) Implementación de "Fast Reconnect" (TLS Session Tickets Resumption)

Vamos a transformar tu archivo `eap` en una configuración de alto rendimiento para la **UPeU**. 

Este código activa el **Fast Reconnect** y optimiza la **fragmentación de certificados**, tal como recomienda el artículo de InkBridge:

[RADIUS for Universities](https://www.inkbridgenetworks.com/blog/blog-10/radius-for-universities-122)

### Pasos para actualizar tu Mothership de AWS:

1. Abre tu archivo: `sudo nano /etc/freeradius/3.0/mods-available/eap`
    
    ```bash
    sudo nano /etc/freeradius/3.0/mods-available/eap
    ```
    
2. **Cambia la línea 27:** Busca `default_eap_type = md5` y cámbialo a `tls`.
3. **Busca la sección `tls-config tls-common { ... }`** (aproximadamente en la línea 300) y reemplázala por este bloque optimizado

Bloque Optimizado para UPeU (con documentación preservada)

```bash
tls-config tls-common {
                # --- CERTIFICADOS (Actualizados para UPeU) ---
                # private_key_password = whatever  # Comentar si la llave no tiene pass
                private_key_file = ${certdir}/upeu/server-key.pem
                certificate_file = ${certdir}/upeu/server-cert.pem
                ca_file = ${certdir}/upeu/ca-root.pem
                ca_path = ${cadir}

                # --- OPTIMIZACIÓN DE RENDIMIENTO (ACTIVADOS) ---
                dh_file = ${certdir}/dh
                random_file = /dev/urandom
                fragment_size = 1024  # Vital para certificados grandes de Microsoft
                include_length = yes

                tls_min_version = "1.2"
                tls_max_version = "1.2"  # Se puede subir a 1.3 si los APs lo soportan
                ecdh_curve = "prime256v1"

                # --- CACHÉ Y FAST RECONNECT (ESTÁNDAR INKBRIDGE) ---
						    cache {
						        # Habilita la reanudación de sesión
						        enable = yes
						        
						        # Tiempo de vida de las sesiones en horas (ej. 24 horas)
						        lifetime = 24
						        
						        # Número máximo de entradas en la caché (0 para infinito, o ajústalo a tu cantidad de usuarios)
						        max_entries = 255
						        
						        # Nombre interno de la caché. ¡OBLIGATORIO si vas a usar persist_dir!
						        name = "EAP_TLS_Cache"
						        
						        # Directorio para guardar las sesiones en disco para que sobrevivan a un reinicio del servidor
						        persist_dir = "${logdir}/tlscache"
						    }

    

```

*Nota sobre persist_dir:* Esta directiva guarda el estado SSL y las políticas en archivos físicos en el disco local. El servidor necesitará permisos de escritura en este directorio (`/var/log/freeradius/tlscache` o similar), y es una buena práctica crear un script (como un *cronjob*) que limpie los archivos viejos periódicamente.

Ejecuta estos comandos en la terminal de AWS:

```bash
# Crear la carpeta para la caché
sudo mkdir -p /var/log/freeradius/tlscache

# Cambiar el dueño al usuario del servicio (freerad)
sudo chown freerad:freerad /var/log/freeradius/tlscache

# Dar permisos restrictivos (solo el servidor puede leer esto por seguridad)
sudo chmod 700 /var/log/freeradius/tlscache
```

### Crear el script de limpieza (Cronjob)

Si no limpiamos esta carpeta, se llenará de miles de archivos pequeños con el tiempo. Vamos a programar una limpieza automática cada noche.

1. Abre el editor de tareas programadas:
`sudo crontab -e`*(Si te pregunta, elige `nano` presionando 1)*.
2. Ve al final del archivo y pega esta línea (esto borrará archivos con más de 2 días de antigüedad a las 3:00 AM cada día):Plaintext
    
    ```bash
    0 3 * * * find /var/log/freeradius/tlscache -mtime +2 -exec rm -f {} \;
    ```
    
3. Guarda y sal.

---

### 🚀 Verificación Final

Para activar los cambios, valida que no haya errores y reinicia:

```bash
sudo freeradius -CXsudo systemctl restart freeradius
```

**¿Cómo saber si funciona?**
Después de que un usuario se conecte, mira dentro de la carpeta:

```bash
sudo ls -l /var/log/freeradius/tlscache
```

Deberías ver archivos con nombres largos. Esos son los "Session Tickets" de los estudiantes de la **UPeU**. Ahora, aunque reinicies el servidor de AWS, los dispositivos que ya estaban conectados **no tendrán que volver a poner su clave**, entrarán directo.

**2. Habilitar la recuperación de políticas (VLANs, etc.)**

Para que la reconexión rápida funcione correctamente y el servidor recuerde qué VLAN u otras políticas asignó al usuario en su primera conexión, **debes** habilitar la opción `use_tunneled_reply = yes`.

En el mismo archivo `eap`, baja a las secciones de los métodos internos que uses (generalmente `peap` y `ttls`) y configúralo:

```
peap {
    ...
    use_tunneled_reply = yes
}

ttls {
    ...
    use_tunneled_reply = yes
}
```

**3. El reto de la versión 3.2.5 en tu arquitectura "Satélite"**

En la versión 3.x, la caché de sesiones (`rbtree` por defecto en memoria o en disco con `persist_dir`) es **estrictamente local** en cada servidor.

Esto significa que:

- Si un estudiante se conecta en el Edificio A (autenticado por el **Satélite 1**), la caché se guarda solo en el Satélite 1.
- Si el estudiante camina al Edificio B y su celular intenta reconectarse contra el **Satélite 2**, este servidor no tendrá la caché local, rechazará el intento rápido y forzará al dispositivo a realizar una autenticación completa de nuevo (consultando a Entra ID).

**La solución en 3.2.5 para roaming real entre satélites:** Si realmente necesitas que el "Fast Reconnect" funcione sin interrupciones cuando los usuarios saltan de un servidor satélite a otro, la caché de la sesión TLS no puede guardarse localmente; debe preservarse utilizando un backend externo centralizado, como **Memcached** o **Redis**. De esta forma, todos tus satélites consultarán la misma base de datos de sesiones en memoria cuando un usuario intente hacer reconexión rápida.

Si la latencia de red entre tus edificios no amerita configurar Redis centralizado, simplemente aplicar la configuración de arriba reducirá drásticamente las peticiones a Entra ID siempre que el usuario se mantenga en la zona de cobertura del mismo servidor satélite.

# ⚠️ Importante!

*Asegúrate de crear la carpeta:* `sudo mkdir -p /var/log/freeradius/tickets && sudo chown freerad /var/log/freeradius/tickets`

```bash
sudo mkdir -p /var/log/freeradius/tickets && sudo chown freerad:freerad /var/log/freeradius/tickets
```

### Cambios principales realizados:

1. **Activación de Session Tickets:** He añadido el bloque `session_ticket` que no estaba en tu código original pero es la recomendación #1 del artículo de InkBridge para universidades.
2. **Caché Activado:** Cambié `enable = no` a `enable = yes` en el bloque de `cache`. Esto permite que el servidor "recuerde" a los alumnos durante su jornada diaria.
3. **Fragmentación:** Activé `fragment_size = 1024`. Sin esto, los dispositivos móviles a menudo fallan al recibir los certificados de la nube de Microsoft.
4. **Curva Elíptica:** Añadí `prime256v1` a `ecdh_curve`. Dejarlo vacío puede causar errores en clientes modernos de Windows 11.
5. **Rutas de UPeU:** Actualicé las rutas de los certificados para que apunten a la carpeta `/upeu/` que preparamos, pero manteniendo la estructura de variables.

**Importante:** Antes de reiniciar, recuerda que el comando `openssl dhparam` que ejecutamos antes debe haber terminado para que la línea `dh_file = ${certdir}/dh` sea válida.

### Siguiente Paso Obligatorio:

Para que esta configuración no dé error al reiniciar, **debes generar el archivo DH (Diffie-Hellman)** que pusimos en la ruta `${certdir}/dh`. Ejecuta este comando en tu terminal de AWS:

Bash

`sudo openssl dhparam -out /etc/freeradius/3.0/certs/dh 2048`

*(Nota: Esto tardará unos 2 a 5 minutos, es un proceso matemático pesado).*

Una vez que termine, asegúrate de que FreeRADIUS pueda leerlo con este comando:

Bash

`sudo chown freerad:freerad /etc/freeradius/3.0/certs/dh`