# Instalación en Ubuntu:

## Instalación inicial

Una vez que termine la instalación de Ubuntu y logres iniciar sesión, lo primero es instalar el servidor y las herramientas necesarias:

```bash
sudo apt update
sudo apt install freeradius freeradius-utils -y
```

**Verifica que el servidor esté activo:**
Una vez termine, puedes verificar que el "server" está ahí corriendo con:Bash

```bash
systemctl status freeradius
```

---

### Un detalle importante para tu configuración de "Esclavo":

Como este servidor `vmware01` (`172.16.79.129`) será un **Proxy**, después de instalarlo lo primero que haremos será detener el servicio automático para configurarlo manualmente y probar la conexión hacia AWS.