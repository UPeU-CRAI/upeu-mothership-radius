# 8 (3)Aumentar la capacidad de procesamiento de ambos servidores

### Performance Optimization (Tuning de Hilos)

InkBridge advierte sobre los "picos" de inicio de clase. Debemos aumentar la capacidad de procesamiento de ambos servidores (Master y Esclavo) para que no "encolen" peticiones.

**En ambos servidores, edita `/etc/freeradius/3.0/radiusd.conf`:**

```bash
**sudo nano /etc/freeradius/3.0/radiusd.conf**
```

Busca la sección `thread pool` y ajusta estos valores:

Fragmento de código

```bash
thread pool {
        start_servers = 10
		    max_servers = 150       # Aumentado para manejar ráfagas de alumnos
		    min_spare_servers = 5
		    max_spare_servers = 20
    
		    # Limita las peticiones por hilo para evitar fugas de memoria
		    max_requests_per_server = 1000
}
```