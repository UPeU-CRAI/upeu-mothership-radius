# Despliegue de la Instancia FreeRADIUS en AWS

> **Rol:** Infraestructura de la Mothership (servidor RADIUS Master)  
> **Referencia:** [InkBridge Networks — RADIUS for Universities](https://www.inkbridgenetworks.com/blog/blog-10/radius-for-universities-122)  
> **Siguiente paso:** [Configuración RADIUS](configuracion-radius.md)

---

## 1. Lanzamiento de la Instancia EC2

Para mantenerte en el **Free Tier**, elige:

| Parámetro | Valor |
|---|---|
| **Nombre** | `FreeRADIUS-Master-UPeU` |
| **AMI** | Ubuntu Server 24.04 LTS |
| **Tipo de instancia** | `t2.micro` |
| **Key Pair** | Crear uno nuevo y guardarlo en un lugar seguro |
| **Auto-assign public IP** | Enable (temporal, luego se fija con Elastic IP) |

---

## 2. Configuración del Security Group

Crea un grupo llamado `RADIUS-Master-SG` con las siguientes reglas de entrada:

### Regla para Autenticación (Puerto 1812)
| Campo | Valor |
|---|---|
| **Type** | Custom UDP |
| **Port range** | `1812` |
| **Source** | IP pública de la sede UPeU (ej: `200.1.2.3/32`) |
| **Description** | `RADIUS Auth desde Sede Lima` |

### Regla para Contabilidad (Puerto 1813)
| Campo | Valor |
|---|---|
| **Type** | Custom UDP |
| **Port range** | `1813` |
| **Source** | Misma IP de la sede |
| **Description** | `RADIUS Acct desde Sede Lima` |

### Regla SSH (Ajuste de Seguridad)
| Campo | Valor |
|---|---|
| **Type** | SSH |
| **Port range** | `22` |
| **Source type** | `My IP` |

> [!WARNING]
> No dejes SSH con `Anywhere (0.0.0.0/0)`. Restringe el acceso solo a tu IP para prevenir ataques de fuerza bruta.

---

## 3. Elastic IP (IP Fija)

> [!IMPORTANT]
> Después de lanzar la instancia, **crea una Elastic IP** y asóciala a la máquina. Si no lo haces, cada reinicio cambiará la IP y los Satellites perderán conexión con la Mothership.

---

## 4. Instalación de FreeRADIUS

Una vez conectado por SSH a la instancia:

```bash
# Actualizar repositorios y sistema
sudo apt update && sudo apt upgrade -y

# Instalar FreeRADIUS y herramientas
sudo apt install freeradius freeradius-utils -y
```

### Verificar la instalación

```bash
sudo freeradius -v
```

Deberías ver la versión `3.x` en la salida.

> [!TIP]
> Si aparece el mensaje `Pending kernel upgrade!`, reinicia la instancia antes de continuar:
> ```bash
> sudo reboot
> ```
> Espera un minuto y vuelve a conectarte por SSH.

---

## 5. Verificación de Configuración Post-Instalación

Valida que la configuración base no tenga errores:

```bash
sudo freeradius -CX
```

Si al final dice `Configuration appears to be OK`, la instalación fue exitosa.
