# Perfiles Intune — SCEP y Wi-Fi

Configuración de perfiles de certificados y Wi-Fi en Microsoft Intune para distribución automática a dispositivos de la UPeU.

---

## Checklist de Configuración

- [ ] **Paso A:** Crear Perfil de Certificado de Confianza (Root CA)
- [ ] **Paso B:** Crear Perfil SCEP (Certificado del alumno)
- [ ] **Paso C:** Crear Perfil Wi-Fi (Conexión automática)
- [ ] Asignar perfiles a grupos de prueba
- [ ] Verificar despliegue en dispositivos

---

## Paso A: Perfil de Certificado de Confianza

Antes de solicitar un certificado SCEP, el dispositivo debe confiar en la entidad emisora.

1. En Intune, ve a **Dispositivos** > **Configuración** > **+ Crear** > **+ Nueva directiva**

   ![Crear nueva directiva](../assets/capturas/intune-crear-directiva.png)

2. **Plataforma:** Windows 10 y versiones posteriores
3. **Tipo de perfil:** Selecciona **Plantillas** (Templates)
4. Busca **Certificado de confianza** (Trusted certificate)

   ![Seleccionar certificado de confianza](../assets/capturas/intune-certificado-confianza.png)

5. **Nombre:** `UPeU - Certificado Raíz de Confianza`
6. **Configuración:** Sube el archivo `.cer` de tu **Root CA** (descargado de Cloud PKI)
7. **Asignación:** Asígnalo a un grupo de usuarios o dispositivos de prueba

---

## Paso B: Perfil SCEP (Certificado del Alumno)

Este perfil genera un certificado único para cada alumno/dispositivo.

### Referencias
- [How-To: Create Intune SCEP Profiles for Windows Devices](https://www.keytos.io/docs/azure-pki/how-to-create-scep-ca-in-azure/how-to-issue-certificates-with-mdm/intune-certificate-authority/create-intune-certificate-profiles/create-windows-intune-scep-profiles/)
- [Video: Network Certificate Based Authentication with Intune and Cloud RADIUS in Unifi](https://www.youtube.com/watch?v=2kijpP0gpk8)

### Pasos

1. Ve a **Dispositivos** > **Configuración** > **+ Crear** > **+ Nueva directiva**
2. **Plataforma:** Windows 10 y versiones posteriores
3. **Tipo de perfil:** **Plantillas** > **Certificado SCEP**

   ![Seleccionar certificado SCEP](../assets/capturas/intune-scep-template.png)

4. **Configuración clave:**

| Campo | Valor |
|---|---|
| **Tipo de certificado** | Usuario (se liga al correo del alumno) |
| **Formato del nombre del sujeto** | `CN={{UserEmail}}` |
| **Nombre alternativo del sujeto** | UPN: `{{UserPrincipalName}}` |
| **Periodo de validez** | 1 año |
| **KSP** | Software (o TPM si hay chip de seguridad) |
| **Uso de claves** | Firma digital + Cifrado de claves |
| **Uso extendido de claves** | Autenticación de cliente |
| **Certificado de confianza raíz** | Seleccionar el perfil del Paso A |
| **URL del servidor SCEP** | URL de la Issuing CA (ver Cloud PKI) |

   ![Configuración SCEP URL](../assets/capturas/intune-scep-url.png)

   ![Configuración SCEP detalle](../assets/capturas/intune-scep-detalle.png)

5. **Asignación:** Asignar a grupo de prueba

   ![Asignación de perfil](../assets/capturas/intune-asignacion.png)

> [!IMPORTANT]
> Repite la asignación tanto para **usuarios** como para **dispositivos** si es necesario.

   ![Asignación dispositivos](../assets/capturas/intune-asignacion-dispositivos.png)

   ![Verificación final](../assets/capturas/intune-verificacion.png)

---

## Paso C: Perfil Wi-Fi (Pendiente)

> [!NOTE]
> Documentar la creación del perfil Wi-Fi que use el certificado SCEP para autenticación EAP-TLS automática.

- [ ] Crear perfil Wi-Fi empresarial
- [ ] Configurar EAP-TLS como método de autenticación
- [ ] Seleccionar el certificado SCEP como credencial
- [ ] Asignar a grupos correspondientes
