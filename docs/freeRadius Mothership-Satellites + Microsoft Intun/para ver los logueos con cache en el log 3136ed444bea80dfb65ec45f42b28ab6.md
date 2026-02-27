# para ver los logueos con cache en el log

Sigue estos pasos en tu **Satellite (Lima)**:

1. **Edita el archivo**: `sudo nano /etc/freeradius/3.0/sites-enabled/default`
2. **Busca la sección `authorize`** y reemplaza el bloque del `if (ok)` por este, que usa `update reply` (una instrucción que el servidor siempre entiende):

Plaintext

```bash
    cache
    if (ok) {
        # Esto guarda el mensaje en la respuesta y se verá en el log de 'Auth'
        update reply {
            &Reply-Message += ">>> CACHE HIT: Usuario %{User-Name} autenticado desde memoria local en Lima"
        }
        update control {
            Auth-Type := Accept
        }
    }
```

---

### 🚀 Cómo verificar que ahora sí está bien

Antes de intentar reiniciar el servicio (que es lo que te está fallando), ejecuta este comando para que el servidor te diga "en tu cara" si hay algún error:

> **`sudo freeradius -CX`**
> 
- **Si al final dice `Configuration appears to be OK`**: ¡Victoria! Ya puedes reiniciar:
    
    ```bash
    sudo systemctl restart freeradius
    ```
    
- **Si sale algún error**: Por favor, pásame las últimas 5 líneas. Es probable que haya quedado alguna llave `{` abierta o un punto y coma `;` perdido de los intentos anteriores.