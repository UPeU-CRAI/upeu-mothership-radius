# Persistencia y Caché TLS

Configuración de TLS Session Tickets y caché en disco para **Fast Reconnect** en la Mothership y Satellites.

---

## Concepto: Fast Reconnect

Cuando un usuario ya se autenticó por EAP-TLS, el servidor genera un **Session Ticket**. Si el dispositivo se reconecta dentro del periodo de caché (24h), no se necesita un nuevo handshake completo ni consultar a Entra ID → el usuario entra instantáneamente.

---

## 1. Crear Carpeta de Caché

```bash
# Crear la carpeta para la caché
sudo mkdir -p /var/log/freeradius/tlscache

# Asignar propiedad al usuario del servicio
sudo chown freerad:freerad /var/log/freeradius/tlscache

# Permisos restrictivos (solo el servidor puede leer)
sudo chmod 700 /var/log/freeradius/tlscache
```

---

## 2. Crear Carpeta de Session Tickets

```bash
sudo mkdir -p /var/log/freeradius/tickets && sudo chown freerad:freerad /var/log/freeradius/tickets
```

---

## 3. Verificar que la Caché Funciona

Después de que un usuario se conecte, verifica que se crearon archivos de sesión:

```bash
sudo ls -l /var/log/freeradius/tlscache
```

Deberías ver archivos con nombres largos (hexadecimales). Esos son los **Session Tickets** de los dispositivos autenticados.

> [!TIP]
> Aunque reinicies el servidor de AWS, los dispositivos que ya estaban conectados **no tendrán que volver a autenticarse** — entrarán directo gracias a `persist_dir`.

---

## 4. Limpieza Automática (Cronjob)

Sin limpieza, la carpeta se llenará de miles de archivos. Programa una limpieza nocturna:

```bash
# Abrir editor de tareas programadas
sudo crontab -e
```

Agrega esta línea al final (limpia archivos con más de 2 días a las 3:00 AM):

```bash
0 3 * * * find /var/log/freeradius/tlscache -mtime +2 -exec rm -f {} \;
```

---

## 5. Consideraciones para Arquitectura Multi-Satellite

> [!IMPORTANT]
> En FreeRADIUS 3.x la caché de sesiones TLS es **local** en cada servidor.

**Implicación:** Si un estudiante se conecta en el Edificio A (Satellite 1) y camina al Edificio B (Satellite 2), este segundo servidor **no tendrá la caché** y forzará una autenticación completa.

### Solución para Roaming Real
Para que el Fast Reconnect funcione entre múltiples Satellites, se necesita un **backend centralizado** como:
- **Redis**
- **Memcached**

Todos los Satellites consultarían la misma base de datos de sesiones.

> [!NOTE]
> Si la latencia entre edificios no es crítica, la configuración local ya reduce drásticamente las peticiones a Entra ID mientras el usuario se mantenga en la zona del mismo Satellite.
