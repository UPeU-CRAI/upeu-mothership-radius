# 4. Configurar Los Certificados Cloud PKI de UPeU en Intune (INCOMPLETO)

Ahora que el software está instalado, necesitamos los "documentos de identidad" de tu red. Como vamos a usar **EAP-TLS**, el Master de AWS debe conocer la **Entidad Certificadora (CA)** de Microsoft.

**¿Qué archivos necesitamos exactamente?**
Desde el portal de Intune (Cloud PKI), debes haber descargado:

1. El **Root CA Certificate** (ejemplo: `UPeU_Root.cer`)
2. El **Issuing CA Certificate** (ejemplo: `UPeU_Issuing.cer`)

**¿Cómo los subimos al servidor de AWS?**
Si estás en Windows, la forma más fácil es usar **WinSCP** o **FileZilla** usando tu llave `.pem`. Pero si quieres hacerlo por comando desde tu PC (no dentro del servidor), usa esto:

Bash

`# Ejecuta esto en la terminal de TU COMPUTADORA (donde tienes los certificados)
scp -i "tu-llave.pem" C:\ruta\tus-certificados\*.cer ubuntu@TU_IP_ELASTICA:~/`

---

### 4. Preparar la carpeta en el servidor

Una vez que vuelvas a entrar al servidor después del reinicio, mueve los archivos a su lugar definitivo:

Bash

`# Crear la carpeta si no existe
sudo mkdir -p /etc/freeradius/3.0/certs/upeu`

sudo chown -R freerad:freerad /etc/freeradius/3.0/certs/upeu

`# Mueve los certificados (asumiendo que los subiste a tu carpeta personal)
sudo mv ~/*.cer /etc/freeradius/3.0/certs/upeu/`