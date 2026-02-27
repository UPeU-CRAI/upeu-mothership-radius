# Monitoreo y Logs

Comandos y procedimientos para auditar el tráfico de autenticación RADIUS de la UPeU sin interrumpir el servicio.

---

## 1. Verificación de "Hits" en Caché (Satellite Lima)

Cuando un usuario se reconecta usando un **Session Ticket**, el Satellite no consulta a AWS. Puedes ver las reconexiones con:

```bash
sudo tail -f /var/log/freeradius/radius.log | grep "CACHE HIT"
```

**Salida esperada:**
```
>>> CACHE HIT: Usuario alumno@upeu.edu.pe autenticado desde memoria local en Lima
```

> [!TIP]
> Si el log de AWS está en silencio pero el usuario navega, revisa el `Reply-Message` en el log del Satellite. Significa que la caché local está funcionando correctamente.

---

## 2. Logs en Tiempo Real (Mothership AWS)

Para ver nuevas autenticaciones que viajan desde los campus:

```bash
sudo tail -f /var/log/freeradius/radius.log
```

### Filtrar por eventos específicos

```bash
# Solo autenticaciones exitosas
sudo tail -f /var/log/freeradius/radius.log | grep "Access-Accept"

# Solo rechazos
sudo tail -f /var/log/freeradius/radius.log | grep "Access-Reject"

# Solo un usuario específico
sudo tail -f /var/log/freeradius/radius.log | grep "alumno@upeu.edu.pe"
```

---

## 3. Logs del Sistema (journalctl)

Para ver los logs del servicio FreeRADIUS a nivel de sistema:

```bash
# Últimas 50 líneas
sudo journalctl -u freeradius -n 50

# En tiempo real
sudo journalctl -u freeradius -f

# Desde una fecha específica
sudo journalctl -u freeradius --since "2026-02-27 08:00:00"
```

---

## 4. Verificar Estado del Servicio

```bash
# Estado de la Mothership o Satellite
sudo systemctl status freeradius
```

### Tabla de Referencia de Servidores

| Servidor | IP | Comando de monitoreo |
|---|---|---|
| **Mothership (AWS)** | `54.166.108.154` | `sudo tail -f /var/log/freeradius/radius.log` |
| **Satellite (Lima)** | `192.168.62.89` | `sudo tail -f /var/log/freeradius/radius.log \| grep "CACHE HIT"` |

---

## 5. Verificar Caché en Disco

Para ver cuántas sesiones están almacenadas:

```bash
# Contar sesiones activas
sudo ls -1 /var/log/freeradius/tlscache | wc -l

# Ver detalles de las sesiones
sudo ls -la /var/log/freeradius/tlscache
```

> [!NOTE]
> Los archivos en `tlscache` son automáticamente limpiados por el cronjob configurado (archivos con más de 2 días se eliminan a las 3:00 AM).
