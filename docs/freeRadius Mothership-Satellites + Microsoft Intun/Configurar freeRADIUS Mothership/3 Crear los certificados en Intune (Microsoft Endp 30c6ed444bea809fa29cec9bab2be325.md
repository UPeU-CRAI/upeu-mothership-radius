# 3. Crear los certificados en Intune (Microsoft Endpoint Manager) usando Microsoft Cloud PKI

Para crear los certificados en Intune (Microsoft Endpoint Manager) usando **Microsoft Cloud PKI**, debes seguir un orden jerárquico. Primero creas la "madre" (Root) y luego la "hija" (Issuing) que es la que realmente emitirá certificados a las laptops de la UPeU.

Aquí tienes la ruta y el procedimiento exacto:

---

### 1. Crear la Autoridad Certificadora Raíz (Root CA)

Esta es la base de confianza. Solo se crea una vez.

1. Entra al [Centro de administración de Microsoft Intune](https://www.google.com/search?q=https://intune.microsoft.com/).
2. Ve a **Administración del inquilino** (Tenant Administration) > **Cloud PKI**.
3. Haz clic en **Crear** y selecciona **Entidad de certificación raíz**.
4. **Configuración:**
    - **Nombre común (CN):** `UPeU Root CA`
    - **Periodo de validez:** 10 o 20 años (recomendado para la Raíz).
5. Finaliza el asistente. Una vez creada, entra en ella y haz clic en **Descargar certificado** (será un archivo `.cer`). **Guárdalo, lo subiremos a AWS.**

---

### 2. Crear la Autoridad Certificadora emisora (Issuing CA)

Esta es la que FreeRADIUS consultará y la que Intune usará para repartir certificados.

1. En la misma pantalla de **Cloud PKI**, haz clic en **Crear** y selecciona **Entidad de certificación emisora**.
2. **Configuración:**
    - **Nombre común (CN):** `UPeU Issuing CA Wi-Fi`
    - **Tipo de CA:** Selecciona **Raíz de Cloud PKI** (y elige la que creaste en el paso anterior).
    - **Periodo de validez:** 2 a 5 años.
3. En la sección de **Atributos**, verás las URLs de **CRL** (lista de revocación) y **SCEP**. Copia estas URLs en un Notepad, las podrías necesitar luego.
4. Finaliza y **Descarga el certificado** de esta Issuing CA también.

---

### 3. Crear el Perfil de Certificado

### **Paso A: Crear el Perfil de Certificado de Confianza (Indispensable)**

Antes de pedir un certificado (SCEP), la laptop debe confiar en la entidad que lo emite.

1. En Intune, ve a **Dispositivos** > **Configuración** > + **Crear > + Nueva directiva**
    
    ![Captura de pantalla 2026-02-19 a la(s) 5.07.34 p. m..png](3%20Crear%20los%20certificados%20en%20Intune%20(Microsoft%20Endp/a4e90a95-c79f-4aab-ab23-d7842d220a50.png)
    
2. **Plataforma:** Windows 10 y versiones posteriores.
3. **Tipo de perfil:** Selecciona **Plantillas** (Templates).
4. Busca en la lista **Certificado de confianza** (Trusted certificate).
    
    ![Captura de pantalla 2026-02-19 a la(s) 5.09.22 p. m..png](3%20Crear%20los%20certificados%20en%20Intune%20(Microsoft%20Endp/Captura_de_pantalla_2026-02-19_a_la(s)_5.09.22_p._m..png)
    
5. Ponle de nombre: `UPeU - Certificado Raíz de Confianza`.
6. En la configuración, **sube el archivo `.cer` de tu Root CA** que descargaste de Cloud PKI.
7. **Asignación:** Asígnalo a un grupo de usuarios o dispositivos de prueba.

Paso B: Crear el Perfil SCEP (El que genera el certificado del alumno)

[How-To: Create Intune SCEP Profiles for Windows Devices](https://www.keytos.io/docs/azure-pki/how-to-create-scep-ca-in-azure/how-to-issue-certificates-with-mdm/intune-certificate-authority/create-intune-certificate-profiles/create-windows-intune-scep-profiles/)

[How to do Network Certificate Based Authentication with Intune and Cloud RADIUS in Unifi](https://www.youtube.com/watch?v=2kijpP0gpk8)

1. Ve a **Dispositivos** > **Configuración** > + **Crear > + Nueva directiva**
    
    ![Captura de pantalla 2026-02-19 a la(s) 5.07.34 p. m..png](3%20Crear%20los%20certificados%20en%20Intune%20(Microsoft%20Endp/a4e90a95-c79f-4aab-ab23-d7842d220a50.png)
    
2. Plataforma: **Windows 10 y versiones posteriores**.
3. Tipo de perfil: **Plantillas** > **Certificado SCEP**.
    
    ![Captura de pantalla 2026-02-19 a la(s) 5.12.12 p. m..png](3%20Crear%20los%20certificados%20en%20Intune%20(Microsoft%20Endp/Captura_de_pantalla_2026-02-19_a_la(s)_5.12.12_p._m..png)
    
4. **Configuración clave:**
    - **Tipo de certificado:** Usuario (así el certificado se liga al correo del alumno).
    - **Formato del nombre del sujeto:** `CN={{UserEmail}}` (Esto es vital para que FreeRADIUS sepa quién es el usuario).
    - **Nombre alternativo del sujeto:** Agrega un atributo de "Nombre principal del usuario (UPN)" con el valor `{{UserPrincipalName}}`.
    - **Periodo de validez:** 1 año (o lo que prefieras).
    - **Proveedor de almacenamiento de claves (KSP):** Inscribir en KSP de software (o TPM si las laptops tienen chip de seguridad).
    - **Uso de claves:** Firma digital y Cifrado de claves.
    - **Uso extendido de claves:** Selecciona "Autenticación de cliente" de la lista predefinida.
    - **Certificado de confianza de raíz:** Selecciona el perfil que creamos en el **Paso A**.
    - **Direcciones URL del servidor SCEP:** Aquí pegas la URL larga que te dio la **Issuing CA** en el panel de Cloud PKI.
        
        ![Captura de pantalla 2026-02-19 a la(s) 5.43.55 p. m..png](3%20Crear%20los%20certificados%20en%20Intune%20(Microsoft%20Endp/Captura_de_pantalla_2026-02-19_a_la(s)_5.43.55_p._m..png)
        
        ![Captura de pantalla 2026-02-19 a la(s) 5.46.43 p. m..png](3%20Crear%20los%20certificados%20en%20Intune%20(Microsoft%20Endp/Captura_de_pantalla_2026-02-19_a_la(s)_5.46.43_p._m..png)
        
5. Asigna este perfil a un grupo de prueba (tus dispositivos).
    
    ![Captura de pantalla 2026-02-19 a la(s) 5.48.12 p. m..png](3%20Crear%20los%20certificados%20en%20Intune%20(Microsoft%20Endp/Captura_de_pantalla_2026-02-19_a_la(s)_5.48.12_p._m..png)
    
    ### Lo mismo que se hizo con los usuarios hacer con los dispositivos
    
    ![Captura de pantalla 2026-02-19 a la(s) 5.53.27 p. m..png](3%20Crear%20los%20certificados%20en%20Intune%20(Microsoft%20Endp/Captura_de_pantalla_2026-02-19_a_la(s)_5.53.27_p._m..png)
    
    ![Captura de pantalla 2026-02-19 a la(s) 5.56.01 p. m..png](3%20Crear%20los%20certificados%20en%20Intune%20(Microsoft%20Endp/Captura_de_pantalla_2026-02-19_a_la(s)_5.56.01_p._m..png)
    

---

![Captura de pantalla 2026-02-19 a la(s) 5.56.53 p. m..png](3%20Crear%20los%20certificados%20en%20Intune%20(Microsoft%20Endp/Captura_de_pantalla_2026-02-19_a_la(s)_5.56.53_p._m..png)

### 4. Resumen de lo que debes tener para AWS

Para que nuestro **FreeRADIUS Master** funcione, necesito que tengas en tu computadora estos dos archivos que descargaste:

1. `UPeU_Root_CA.cer`
2. `UPeU_Issuing_CA.cer`

---

###