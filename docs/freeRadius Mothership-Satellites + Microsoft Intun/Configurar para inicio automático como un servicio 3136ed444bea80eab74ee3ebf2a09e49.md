# Configurar para inicio automático como un servicio estable de fondo

Este es un paso fundamental para la estabilidad de la red de la **UPeU**. Al pasar a "modo servicio", el servidor se ejecutará en segundo plano, se reiniciará solo si hay un fallo y arrancará automáticamente si el servidor físico o la VM se reinician.

Sigue estos pasos en **ambos servidores** (Mothership en AWS y Satellite en Lima):

**1. Detener el modo Debug**
En ambas terminales donde tienes corriendo el `freeradius -X`:
1. Presiona **`Ctrl + C`** para detener el proceso actual.

**2. Verificar la sintaxis de configuración**
Antes de lanzarlo al fondo, asegúrate de que no haya errores de escritura en los archivos que editamos (`users`, `clients.conf`, `proxy.conf`).
• Ejecuta: `sudo freeradius -C`
• **Resultado esperado**: Debería terminar sin errores (si hay un error, te dirá exactamente en qué línea de qué archivo está).

**3. Activar el servicio estable (Systemd)**
Ejecuta estos tres comandos en orden:
• **Iniciar el servicio ahora**:

```bash
sudo systemctl start freeradius
```

• Configurar el arranque automático al encender el servidor:

```bash
sudo systemctl enable freeradius
```

• Verificar que esté corriendo correctamente:

```bash
sudo systemctl status freeradius
```

**4. Cómo monitorear sin el modo Debug**
Ya no verás el texto desplazándose automáticamente, pero puedes "espiar" lo que sucede en tiempo real usando los logs del sistema. Esto es lo que harás a partir de ahora para ver si alguien se conecta:

- Para ver los intentos de conexión (Auth Logs):

```bash
sudo tail -f /var/log/freeradius/radius.log
```

| **Servidor** | **IP** | **Estado de Servicio** |
| --- | --- | --- |
| **Mothership (AWS)** | `54.166.108.154` | `active (running)` |
| **Satellite (Lima)** | `192.168.62.89` | `active (running)` |
- Nota importante: Si después de hacer esto el WiFi deja de funcionar, revisa los permisos de los archivos que editamos. A veces el modo debug (-X) corre como root y tiene permisos que el servicio estándar no tiene. Si sucede, ejecuta:

```bash
sudo chown -R freerad:freerad /etc/freeradius/3.0/
```