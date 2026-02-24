# UPeU Mothership RADIUS 🚀

Repositorio central de autenticación basado en la metodología de **InkBridge Networks** y estándares **Cisco AAA**.

## 🛠 Stack Tecnológico
* **Identity:** Microsoft Entra ID + Microsoft Cloud PKI.
* **Endpoint Management:** Microsoft Intune (SCEP/SCEP profiles).
* **Policy Server:** FreeRADIUS 3.0 en AWS EC2 (Ubuntu).
* **Satellites:** Ubiquiti UniFi APs (Sede Lima/Juliaca/Tarapoto).

## 📐 Arquitectura
[Aquí insertaremos el diagrama Mermaid que diseñamos]

## 📋 Cumplimiento
- **Authentication:** EAP-TLS (Certificados digitales).
- **Authorization:** Role-Based Access Control (RBAC) via Entra Groups.
- **Accounting:** Interim-Update centralizado en AWS.

## 📁 Estructura del Repositorio

```
upeu-mothership-radius/
│
├── infrastructure/
│   └── aws/                  # Código IaC para levantar el servidor (Terraform)
│
├── freeradius/
│   ├── clients.d/            # Definición de APs Satélites (clientes Cisco AAA)
│   └── certs/                # Gestión de certificados Cloud PKI (Microsoft Entra ID)
│
├── intune/
│   └── profiles/             # Export de políticas de Microsoft Intune (SCEP/Wi-Fi)
│
├── docs/
│   └── architecture/         # Documentación de arquitectura (InkBridge / Antigravity)
│
└── .github/
    └── workflows/            # Automatización CI/CD (GitHub Actions)
```