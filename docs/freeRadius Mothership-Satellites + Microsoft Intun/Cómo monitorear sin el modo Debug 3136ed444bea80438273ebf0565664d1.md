# Cómo monitorear sin el modo Debug

Primero se debe modificar los logs (o cualquier parámetro global del servidor), usa:

Bash

`sudo nano /etc/freeradius/3.0/radiusd.conf`

Dentro del archivo, busca la sección **`log { ... }`** (puedes presionar `Ctrl + W` y escribir "log" para llegar rápido). Verás algo como esto:

Plaintext

```bash
log {
    destination = files
    colourise = yes
    file = ${logdir}/radius.log
    syslog_facility = daemon
    stripped_names = no
    auth = no             # <--- CAMBIA A "yes" PARA VER LOS LOGINS
    auth_badpass = no     # <--- CAMBIA A "yes" PARA VER LAS CLAVES ERRÓNEAS
    auth_goodpass = no    # <--- CAMBIA A "yes" PARA VER LAS CLAVES CORRECTAS
}
```

---

### ⚠️ ¡No olvides el reinicio!

Recuerda que como ahora FreeRADIUS corre como un servicio de fondo (`systemd`), cualquier cambio en este archivo **no tendrá efecto** hasta que reinicies el proceso:

```bash
sudo systemctl restart freeradius
```

---

### 💡 Un pequeño consejo de "Mothership" vs "Satellite"

- **En la Mothership (AWS):** Te conviene activar `auth = yes` para tener un registro histórico de quién entra a la universidad.
- **En el Satellite (Lima):** Podrías dejarlo en `no` para ahorrar espacio en disco, ya que la Mothership ya está guardando la auditoría principal.

Esto es lo que harás para ver si alguien se conecta:

- Para ver los intentos de conexión (Auth Logs):

```bash
sudo tail -f /var/log/freeradius/radius.log
```