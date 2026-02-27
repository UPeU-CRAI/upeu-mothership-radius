# 2. Instalar y configurar freeRadius Master en AWS

### Actualización e Instalación

Primero, pongamos al día el sistema e instalemos el software necesario.

Bash

```bash
# Actualiza los repositorios y el sistema
sudo apt update && sudo apt upgrade -y

# Instala FreeRADIUS y las herramientas de red
sudo apt install freeradius freeradius-utils -y
```

Para verificar que se instaló correctamente, corre: `radiusd -v`. Deberías ver la versión 3.x.

```bash
sudo freeradius -v
```

![Captura de pantalla 2026-02-19 a la(s) 4.18.58 p. m..png](2%20Instalar%20y%20configurar%20freeRadius%20Master%20en%20AWS/Captura_de_pantalla_2026-02-19_a_la(s)_4.18.58_p._m..png)

En tu log aparece un mensaje importante: `Pending kernel upgrade!`. AWS actualizó el núcleo de tu servidor. Para que todo funcione de forma estable, te recomiendo reiniciar la instancia ahora mismo:

Bash

```bash
sudo reboot
```

*Espera un minuto y vuelve a entrar por SSH*2. Configuración de Seguridad Inicial

---