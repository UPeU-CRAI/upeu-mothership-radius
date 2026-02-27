# 1. Crear instancia freeRADIUS Master en AWS

## 1. Lanzamiento de la Instancia en AWS (Consola)

Para mantenerte en el **Free Tier**, elige lo siguiente:

- **Nombre:** `FreeRADIUS-Master-UPeU`
- **AMI (Imagen):** Ubuntu Server 24.04 LTS (es la más documentada para FreeRADIUS).
- **Tipo de instancia:** `t2.micro` .
- **Key Pair:** Crea uno y guárdalo bien (lo usarás para entrar por SSH).

Para que el **FreeRADIUS Master** pueda recibir las peticiones de tus sedes de la UPeU, necesitamos agregar las reglas de tráfico RADIUS. Sigue estos pasos en esa misma pantalla antes de lanzar la instancia:

- **Network Settings (Security Group):** Crea un grupo nuevo llamado `RADIUS-Master-SG` con estas reglas de entrada:

## 2. Agregar las Reglas de RADIUS

Haz clic en el botón **"Add security group rule"** dos veces para agregar las siguientes reglas:

### Regla para Autenticación (Puerto 1812)

- **Type:** Selecciona `Custom UDP`.
- **Protocol:** UDP.
- **Port range:** `1812`.
- **Source type:** Aquí te recomiendo elegir `Custom`.
- **Source:** Introduce la **IP Pública** de la sede de la UPeU (ejemplo: `200.1.2.3/32`).
    - *Nota: Si aún no la sabes, puedes poner `Anywhere` (0.0.0.0/0) temporalmente para pruebas, pero recuerda cerrarlo después por seguridad.*
- **Description:** `RADIUS Auth desde Sede Lima`.

### Regla para Contabilidad (Puerto 1813)

- **Type:** Selecciona `Custom UDP`.
- **Protocol:** UDP.
- **Port range:** `1813`.
- **Source type:** Igual que el anterior.
- **Source:** La misma IP de la sede.
- **Description:** `RADIUS Acct desde Sede Lima`.

---

## 3. Ajuste de Seguridad para SSH

En tu captura, la regla de SSH tiene el origen como **"Anywhere" (0.0.0.0/0)**.

- **Recomendación:** Cambia el **Source type** a `My IP`. Esto evitará que cualquier persona en el mundo intente atacar por fuerza bruta tu acceso al servidor. Solo tú desde tu conexión actual podrás entrar.

---

## 4. Verificación de "Auto-assign public IP"

Veo que en la sección superior de tu captura tienes **Auto-assign public IP** en **"Enable"**. Esto es correcto para que puedas conectarte inicialmente.

> **Recordatorio importante:** Como mencionamos antes, después de lanzar la instancia, deberás crear una **Elastic IP** y asociarla a esta máquina. Si no lo haces, cada vez que reinicies el servidor en AWS, la IP cambiará y tus proxies locales en la UPeU perderán la conexión con el Master.
> 

---

## … Próximo paso: Lanzar instancia y Fijar la dirección IP a la instancia de freeRADIUS