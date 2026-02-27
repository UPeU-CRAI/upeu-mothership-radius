# X Preparación para eduroam (RadSec)

El artículo menciona que las universidades suelen participar en redes globales de roaming.

- **Lo que dice el artículo:** El sistema debe ser capaz de manejar peticiones de visitantes de otras instituciones.
- **Acción necesaria:** Implementar **RadSec** (RADIUS sobre TLS) en la Mothership. Esto protege el tráfico RADIUS a través de internet con certificados más robustos que el simple "Shared Secret".