# Instalación del Satellite en Ubuntu

Guía de instalación de FreeRADIUS en el servidor local (VMware) que actuará como Satellite / Proxy.

---

## Prerrequisitos

| Parámetro | Valor |
|---|---|
| **Servidor** | `vmware01` |
| **IP Local** | `192.168.62.89` |
| **SO** | Ubuntu Server |
| **Rol** | Proxy RADIUS (Satellite) |

---

## 1. Instalación de FreeRADIUS

```bash
sudo apt update
sudo apt install freeradius freeradius-utils -y
```

### Verificar que el servicio está activo

```bash
systemctl status freeradius
```

---

## 2. Detener el Servicio para Configuración Manual

Como este servidor será un **Proxy**, lo primero es detener el servicio automático para configurarlo y probar la conexión hacia AWS:

```bash
sudo systemctl stop freeradius
```

---

## 3. Modo Debug (Pruebas Iniciales)

Para verificar la configuración en tiempo real:

```bash
# Detener cualquier proceso activo
sudo systemctl stop freeradius

# Forzar cierre de procesos remanentes
sudo pkill -9 freeradius

# Verificar que los puertos están libres
sudo ss -lupn | grep 1812

# Lanzar en modo debug
sudo freeradius -X
```

> [!NOTE]
> Si `ss -lupn | grep 1812` no devuelve nada, los puertos están libres y puedes proceder con el modo debug.

---

## Siguiente Paso

→ [Configuración del Proxy](configuracion-proxy.md): Configurar el reenvío de peticiones hacia la Mothership en AWS.
