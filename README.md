# UPeU Mothership RADIUS 🚀

Repositorio central de autenticación Wi-Fi empresarial para la **Universidad Peruana Unión**, basado en la metodología de [InkBridge Networks](https://www.inkbridgenetworks.com/blog/blog-10/radius-for-universities-122) y estándares **Cisco AAA**.

---

## 📐 Arquitectura

```mermaid
flowchart LR
    subgraph Campus["🏫 Campus Lima"]
        AP["📡 Access Points<br/>Ubiquiti UniFi"]
        SAT["🛰️ SAT-LIMA-01<br/>FreeRADIUS Satellite"]
    end

    subgraph AWS["☁️ AWS Cloud"]
        MOTH["🚀 MOTHERSHIP-AWS<br/>FreeRADIUS Master"]
    end

    subgraph Microsoft["🔐 Microsoft Cloud"]
        ENTRA["Entra ID + Cloud PKI"]
        INTUNE["Intune (SCEP/Wi-Fi)"]
    end

    Device["💻 Dispositivo"] -->|"EAP-TLS"| AP
    AP -->|"RADIUS<br/>UDP 1812"| SAT
    SAT -->|"Proxy"| MOTH
    MOTH -.->|"Valida certs"| ENTRA
    INTUNE -->|"Certificados"| Device

    style MOTH fill:#1a56db,color:#fff
    style SAT fill:#047857,color:#fff
    style AP fill:#7c3aed,color:#fff
    style Device fill:#d97706,color:#fff
```

### Glosario

| Componente | IP | Rol |
|---|---|---|
| **MOTHERSHIP-AWS** | `<IP_ELASTICA_MOTHERSHIP>` | Servidor RADIUS Master (EAP-TLS + validación de certificados + Session Tickets) |
| **SAT-LIMA-01** | `<IP_PUBLICA_SAT_LIMA_01>` | Proxy RADIUS local con caché de atributos (VLAN/Reply-Message) para resiliencia WAN |
| **Access Points** | `172.16.79.0/24` | Ubiquiti UniFi (sede Lima) |

---

## 🛠 Stack Tecnológico

| Capa | Tecnología |
|---|---|
| **Identity** | Microsoft Entra ID + Microsoft Cloud PKI |
| **Endpoint Management** | Microsoft Intune (SCEP / Wi-Fi profiles) |
| **Policy Server** | FreeRADIUS 3.2.x en AWS EC2 (Ubuntu 24.04 LTS) |
| **Satellites** | FreeRADIUS 3.2.x en Ubuntu (VMware local) |

---

## 📋 Cumplimiento

- **Authentication:** EAP-TLS (Certificados digitales)
- **Authorization:** Role-Based Access Control (RBAC) vía Entra Groups
- **Accounting:** Interim-Update centralizado en AWS

---

## 📁 Estructura del Repositorio

```
upeu-mothership-radius/
├── README.md
├── docs/
│   ├── 00-indice.md                    # Índice general + mapa de navegación
│   ├── 01-arquitectura/
│   │   └── flujo-autenticacion.md       # Diagrama y flujo Mothership ↔ Satellites
│   ├── 02-mothership-aws/
│   │   ├── despliegue-instancia.md      # Crear instancia EC2 + instalar FreeRADIUS
│   │   └── configuracion-radius.md      # EAP-TLS + Caché TLS + Zero Trust + Performance
│   ├── 03-satellites-locales/
│   │   ├── instalacion-ubuntu.md        # Instalación en VMware / Ubuntu
│   │   └── configuracion-proxy.md       # Reenvío de peticiones hacia AWS
│   ├── 04-identidad-y-pki/
│   │   ├── microsoft-entra-id.md        # App Registration y App Proxy
│   │   ├── cloud-pki-config.md          # Certificados Root CA e Issuing CA
│   │   └── perfiles-intune.md           # Perfiles SCEP y Wi-Fi (Checklist)
│   ├── 05-operaciones/
│   │   ├── monitoreo-logs.md            # tail, journalctl y verificación de caché
│   │   └── mantenimiento.md             # Rotación de logs y limpieza
│   ├── 06-troubleshooting/
│   │   └── errores-comunes.md           # Soluciones a problemas frecuentes
│   └── assets/
│       └── capturas/                    # Screenshots de Intune y configuración
├── infrastructure/
│   └── aws/                             # IaC Terraform (pendiente)
├── freeradius/
│   ├── clients.d/                       # Fragmentos clients.conf por sede (pendiente)
│   └── certs/                           # Certificados Cloud PKI (pendiente — no commitear llaves privadas)
├── intune/
│   └── profiles/                        # Export de políticas Intune (pendiente)
└── .github/
    └── workflows/                       # CI/CD GitHub Actions (pendiente)
```

---

## 🚀 Guía de Inicio Rápido

1. **Arquitectura** → Leer [flujo-autenticacion.md](docs/01-arquitectura/flujo-autenticacion.md)
2. **Mothership** → Seguir [despliegue-instancia.md](docs/02-mothership-aws/despliegue-instancia.md) y luego [configuracion-radius.md](docs/02-mothership-aws/configuracion-radius.md)
3. **Satellite** → Seguir [instalacion-ubuntu.md](docs/03-satellites-locales/instalacion-ubuntu.md) y luego [configuracion-proxy.md](docs/03-satellites-locales/configuracion-proxy.md)
4. **Certificados** → Configurar [cloud-pki-config.md](docs/04-identidad-y-pki/cloud-pki-config.md) y [perfiles-intune.md](docs/04-identidad-y-pki/perfiles-intune.md)
5. **Operar** → Consultar [monitoreo-logs.md](docs/05-operaciones/monitoreo-logs.md) y [mantenimiento.md](docs/05-operaciones/mantenimiento.md)
6. **Problemas** → Ver [errores-comunes.md](docs/06-troubleshooting/errores-comunes.md)