# Microsoft Cloud PKI — Configuración

Gestión de certificados raíz e intermedios (Issuing CA) en Microsoft Cloud PKI para EAP-TLS.

---

## 1. Crear la Autoridad Certificadora Raíz (Root CA)

Esta es la base de confianza. **Solo se crea una vez.**

1. Entra al [Centro de administración de Microsoft Intune](https://intune.microsoft.com/).
2. Ve a **Administración del inquilino** (Tenant Administration) > **Cloud PKI**.
3. Haz clic en **Crear** y selecciona **Entidad de certificación raíz**.
4. **Configuración:**
   - **Nombre común (CN):** `UPeU Root CA`
   - **Periodo de validez:** 10 o 20 años (recomendado para la Raíz)
5. Finaliza el asistente.
6. Entra en ella y haz clic en **Descargar certificado** (archivo `.cer`).

> [!IMPORTANT]
> Guarda el archivo `UPeU_Root_CA.cer`. Se subirá al servidor de AWS.

---

## 2. Crear la Autoridad Certificadora Emisora (Issuing CA)

Esta es la que FreeRADIUS consultará y la que Intune usará para repartir certificados.

1. En la misma pantalla de **Cloud PKI**, haz clic en **Crear** > **Entidad de certificación emisora**.
2. **Configuración:**
   - **Nombre común (CN):** `UPeU Issuing CA Wi-Fi`
   - **Tipo de CA:** Selecciona **Raíz de Cloud PKI** (elige la del paso anterior)
   - **Periodo de validez:** 2 a 5 años
3. Copia las URLs de **CRL** (lista de revocación) y **SCEP** en un Notepad.
4. **Descarga el certificado** de esta Issuing CA.

---

## 3. Subir los Certificados al Servidor AWS

### Desde tu computadora local (usando SCP):

```bash
scp -i "tu-llave.pem" C:\ruta\tus-certificados\*.cer ubuntu@TU_IP_ELASTICA:~/
```

### En el servidor AWS:

```bash
# Crear carpeta para certificados UPeU
sudo mkdir -p /etc/freeradius/3.0/certs/upeu

# Asignar permisos
sudo chown -R freerad:freerad /etc/freeradius/3.0/certs/upeu

# Mover certificados a su ubicación definitiva
sudo mv ~/*.cer /etc/freeradius/3.0/certs/upeu/
```

---

## 4. Resumen de Archivos Necesarios

Para que FreeRADIUS funcione con EAP-TLS, necesitas tener en el servidor:

| Archivo | Descripción | Ruta en AWS |
|---|---|---|
| `UPeU_Root_CA.cer` | Certificado raíz de confianza | `/etc/freeradius/3.0/certs/upeu/ca-root.pem` |
| `UPeU_Issuing_CA.cer` | Certificado de la CA emisora | `/etc/freeradius/3.0/certs/upeu/` |
| `server-key.pem` | Llave privada del servidor | `/etc/freeradius/3.0/certs/upeu/server-key.pem` |
| `server-cert.pem` | Certificado del servidor | `/etc/freeradius/3.0/certs/upeu/server-cert.pem` |
