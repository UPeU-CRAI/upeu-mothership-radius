# Mantenimiento del Sistema

Procedimientos de mantenimiento rutinario para la infraestructura RADIUS de la UPeU.

---

## 1. Gestión del Servicio FreeRADIUS

### Comandos básicos (Ambos servidores)

```bash
# Iniciar servicio
sudo systemctl start freeradius

# Detener servicio
sudo systemctl stop freeradius

# Reiniciar servicio
sudo systemctl restart freeradius

# Habilitar inicio automático al boot
sudo systemctl enable freeradius

# Verificar estado
sudo systemctl status freeradius
```

### Validar configuración antes de reiniciar

```bash
sudo freeradius -CX
```

> [!WARNING]
> **Siempre** valida con `-CX` antes de reiniciar. Un error de sintaxis dejará la red sin autenticación.

---

## 2. Rotación de Logs

### Verificar tamaño del log actual

```bash
du -sh /var/log/freeradius/radius.log
```

### Configurar logrotate (si no está configurado)

Crea o edita `/etc/logrotate.d/freeradius`:

```
/var/log/freeradius/radius.log {
    weekly
    rotate 12
    compress
    delaycompress
    missingok
    notifempty
    postrotate
        systemctl reload freeradius > /dev/null 2>&1 || true
    endscript
}
```

---

## 3. Limpieza de Caché TLS

### Limpieza manual

```bash
# Ver cuántos archivos hay en caché
sudo ls -1 /var/log/freeradius/tlscache | wc -l

# Limpiar archivos con más de 2 días
sudo find /var/log/freeradius/tlscache -mtime +2 -exec rm -f {} \;
```

### Limpieza automática (Cronjob)

Verificar que el cronjob esté activo:

```bash
sudo crontab -l
```

Debería mostrar:
```
0 3 * * * find /var/log/freeradius/tlscache -mtime +2 -exec rm -f {} \;
```

---

## 4. Permisos (Solución de Problemas Comunes)

Si el servicio falla después de usar el modo debug (`-X`):

```bash
# Restaurar permisos del directorio de configuración
sudo chown -R freerad:freerad /etc/freeradius/3.0/

# Restaurar permisos de la caché
sudo chown freerad:freerad /var/log/freeradius/tlscache
sudo chmod 700 /var/log/freeradius/tlscache
```

---

## 5. Actualizaciones del Sistema

```bash
# Actualizar repositorios y sistema
sudo apt update && sudo apt upgrade -y

# Verificar si hay reinicio pendiente
cat /var/run/reboot-required 2>/dev/null || echo "No reboot required"
```

> [!IMPORTANT]
> Después de una actualización del kernel, **reinicia el servidor** y verifica que FreeRADIUS arranque correctamente.

---

## 6. Modo Debug (Troubleshooting)

Cuando necesites diagnosticar problemas en tiempo real:

```bash
# 1. Detener servicio
sudo systemctl stop freeradius

# 2. Matar procesos remanentes
sudo pkill -9 freeradius

# 3. Verificar puertos libres
sudo ss -lupn | grep 1812

# 4. Lanzar en modo debug
sudo freeradius -X

# 5. Cuando termines, volver al modo servicio
# Ctrl+C para salir del debug
sudo systemctl start freeradius
```
