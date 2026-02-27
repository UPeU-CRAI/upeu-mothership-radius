# Crear el usuario "UPeU-Test” en Mothership

Sigue estos pasos en la **terminal de la Mothership - AWS**:

1. **Abre el archivo de usuarios**:Bash
    
    ```bash
    sudo nano /etc/freeradius/3.0/users
    ```
    
2. **Agrega el usuario al principio del archivo** (justo debajo de los comentarios iniciales):Plaintext
    
    ```bash
    test1  Cleartext-Password := "2026"
    test2  Cleartext-Password := "2026"
    ```
    
    *(Asegúrate de respetar los espacios y las comillas)*.
    
3. **Guarda y Sal**: Presiona `Ctrl+O`, luego `Enter` para guardar, y `Ctrl+X` para salir.

---

### 🚀 Reinicio y Prueba Final

Ahora que el usuario existe en la base de datos de AWS, vamos a ver la magia:

1. **Reinicia el modo Debug en la Mothership**:
    - Presiona `Ctrl+C` para detener el proceso actual.
    - Ejecuta: `sudo freeradius -X`.
2. **Verifica el Satellite**: Asegúrate de que tu servidor de Lima (derecha) también esté corriendo en modo debug (`sudo freeradius -X`).
3. **Conecta tu dispositivo**:
    - Busca la red `wifi-RADIUS-UPeU-Satelite-Lima`.
    - **Usuario**: `upeu-test`
    - **Contraseña**: `universidad2026`

---

### 🔍 ¿Qué deberías ver en las pantallas?

- **En la Mothership (Izquierda)**: Deberías ver una explosión de texto verde que termina con la frase: **`Sending Access-Accept`**.
- **En el Satellite (Derecha)**: Verás que recibe el paquete "Accept" de AWS y se lo entrega al AP UniFi.
- **En tu celular**: ¡Estarás conectado al WiFi con seguridad empresarial!