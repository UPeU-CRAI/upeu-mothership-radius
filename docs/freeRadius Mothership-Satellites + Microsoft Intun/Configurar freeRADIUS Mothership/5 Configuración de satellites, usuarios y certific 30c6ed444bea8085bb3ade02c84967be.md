# 5. Configuración de satellites, usuarios y certificados de prueba de la Mothership (AWS)

---

Entra en el servidor de AWS y aplica los valores que rescatamos. El objetivo aquí es que AWS sea el "Cerebro Central".

1. **Permitir al Satellite de Lima**:
Edita `/etc/freeradius/3.0/clients.conf` y añade al final:Plaintext
    
    ```bash
    sudo nano /etc/freeradius/3.0/clients.conf
    ```
    
    ```bash
    client satellite-lima-01 {
        ipaddr = 190.239.28.70
        secret = upeu_crai_local_2026
        shortname = SAT-LIMA-01
        require_message_authenticator = yes
    }
    ```
    
2. **Cargar los usuarios de prueba**:
Edita `/etc/freeradius/3.0/users` y añade al principio:Plaintext
    
    ```bash
    sudo nano /etc/freeradius/3.0/users
    ```
    
    ```bash
    test1  Cleartext-Password := "2026"
    test2  Cleartext-Password := "2026"
    ```
    
3. **Configurar Certificados Base**:
Abre `/etc/freeradius/3.0/mods-available/eap` y busca la sección `tls-config tls-common`. Asegúrate de que las rutas apunten a los archivos "snakeoil" de tu sistema:Plaintext
    
    ```bash
    sudo nano /etc/freeradius/3.0/mods-available/eap
    ```
    
    ```bash
    private_key_file = /etc/ssl/private/ssl-cert-snakeoil.key
    certificate_file = /etc/ssl/certs/ssl-cert-snakeoil.pem
    ca_file = /etc/ssl/certs/ca-certificates.crt
    ```
    

---