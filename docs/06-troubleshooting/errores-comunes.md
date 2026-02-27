# Errores Comunes y Soluciones

Guía de troubleshooting para los problemas más frecuentes en la infraestructura RADIUS de la UPeU.

---

## 1. "No EAP session matching state"

**Síntoma:** El log muestra `No EAP session matching state` y los dispositivos no se conectan.

**Causa:** El servidor no puede encontrar la sesión EAP correspondiente. Puede ocurrir por:
- Timeout en la comunicación entre Satellite y Mothership
- Caché corrupta
- Reinicio del servidor durante un handshake

**Solución:**
```bash
# 1. Limpiar caché TLS
sudo rm -rf /var/log/freeradius/tlscache/*

# 2. Reiniciar servicio
sudo systemctl restart freeradius

# 3. Pedir al usuario que se desconecte y reconecte
```

---

## 2. Puerto 1812 ya en uso

**Síntoma:** Al lanzar `freeradius -X` aparece error de puerto ya en uso.

**Solución:**
```bash
# Forzar cierre de procesos
sudo pkill -9 freeradius

# Verificar que el puerto está libre
sudo ss -lupn | grep 1812

# Si no devuelve nada, relanzar
sudo freeradius -X
```

---

## 3. Wi-Fi deja de funcionar después del modo Debug

**Causa:** El modo debug (`-X`) corre como `root` y puede modificar permisos de archivos que el servicio `systemd` (usuario `freerad`) no puede leer.

**Solución:**
```bash
sudo chown -R freerad:freerad /etc/freeradius/3.0/
sudo chown -R freerad:freerad /var/log/freeradius/
```

---

## 4. Satellite no puede conectar con la Mothership

**Síntoma:** El Satellite muestra `No response from home server` en modo debug.

**Checklist de verificación:**

| Verificación | Comando |
|---|---|
| Mothership está corriendo | `sudo systemctl status freeradius` (en AWS) |
| Puertos abiertos en Security Group | Verificar reglas UDP 1812/1813 en AWS Console |
| IP correcta en `proxy.conf` | Verificar `ipaddr` en la config del Satellite |
| Secret coincide | Comparar `secret` en `proxy.conf` (Satellite) y `clients.conf` (Mothership) |
| Conectividad de red | `ping 54.166.108.154` desde el Satellite |

---

## 5. Certificados no válidos / EAP-TLS falla

**Síntoma:** `ERROR: TLS Alert` en el log.

**Verificaciones:**
```bash
# Verificar que los certificados existen
ls -la /etc/freeradius/3.0/certs/upeu/

# Verificar que el DH file existe
ls -la /etc/freeradius/3.0/certs/dh

# Verificar permisos
stat /etc/freeradius/3.0/certs/upeu/server-key.pem

# Regenerar DH si es necesario
sudo openssl dhparam -out /etc/freeradius/3.0/certs/dh 2048
sudo chown freerad:freerad /etc/freeradius/3.0/certs/dh
```

---

## 6. Log en silencio (no aparecen autenticaciones)

**Causa posible:** El logging no está habilitado en `radiusd.conf`.

**Solución:** En `/etc/freeradius/3.0/radiusd.conf`, verificar la sección `log`:

```ini
log {
    auth = yes              # Debe estar en "yes"
    auth_badpass = yes      # Para ver intentos fallidos
    auth_goodpass = no      # Mantener en "no" por seguridad
}
```

```bash
sudo systemctl restart freeradius
```

---

## 7. Error de sintaxis en configuración

**Síntoma:** El servicio no arranca después de editar archivos.

**Diagnóstico:**
```bash
# Validar configuración (muestra línea exacta del error)
sudo freeradius -CX
```

> [!TIP]
> El comando `-CX` te dirá exactamente en qué archivo y línea se encuentra el error de sintaxis. Revisa que no hayan quedado llaves `{` abiertas o puntos y coma `;` perdidos.

---

## Tareas Futuras (Pendientes)

Los siguientes items fueron identificados como mejoras futuras:

- [ ] **VLAN Assignment:** Configurar atributos `Tunnel-Type`, `Tunnel-Medium-Type` y `Tunnel-Private-Group-ID` en la respuesta de la Mothership
- [ ] **Health Check:** Implementar verificación en `proxy.conf` para que el Satellite detecte si la Mothership se cae y use respaldo local
- [ ] **eduroam (RadSec):** Preparar la Mothership para participar en redes globales de roaming universitario mediante RADIUS sobre TLS
