# Poner Servidor RADIUS en modo Debug

Para verificar que el esclavo puede hablar con el Master, vamos a detener el servicio y lanzarlo en modo debug:

### **Detén el servicio:**

```bash
sudo systemctl stop freeradius
```

### **Fuerza el cierre de cualquier proceso de RADIUS:**

Ejecuta este comando para "matar" cualquier proceso que esté usando los puertos de FreeRADIUS:

Bash

```bash
sudo pkill -9 freeradius
```

*(Si te dice que no encontró nada, no te preocupes, es solo para asegurar).*

### **Verifica que no haya nadie escuchando en esos puertos:**

Bash

```bash
sudo ss -lupn | grep 1812
```

Si el comando no devuelve nada, los puertos están libres.

### **Lanza el debug:**

```bash
sudo freeradius -X
```