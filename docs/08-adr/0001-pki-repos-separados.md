# ADR-0001: La PKI vive en repositorios separados

- **Estado:** Aprobado
- **Fecha:** 2026-03-10
- **Decisores:** Arquitectura de Red y Seguridad UPeU (DTI)
- **Ámbito:** Proyecto Wi-Fi empresarial Mothership-Satellite

---

## Contexto

El repositorio `upeu-mothership-radius` centraliza la arquitectura y operación de FreeRADIUS para autenticación Wi-Fi empresarial mediante EAP-TLS.

La infraestructura PKI corporativa requiere:

- Gobierno criptográfico estricto.
- Ciclos de cambio distintos al plano AAA de red.
- Controles de acceso más restrictivos para material sensible.
- Evidencia de auditoría separada para cumplimiento y seguridad.

---

## Decisión

Se adopta una arquitectura con **separación de repositorios por dominio**:

1. `upeu-mothership-radius`: diseño y operación de RADIUS Mothership-Satellite.
2. `upeu-pki-architecture`: arquitectura de confianza PKI, políticas y modelo de gobierno.
3. `upeu-ejbca-pki`: implementación técnica y operación de la plataforma EJBCA.

En consecuencia, este repositorio solo contendrá documentación de integración (interfaces, flujos y dependencias), sin detalles operativos internos de PKI.

---

## Consecuencias

### Positivas

- Menor riesgo de exposición de secretos y artefactos de CA.
- Auditoría más limpia por responsabilidad técnica.
- Menor acoplamiento entre evolución de RADIUS y evolución de PKI.
- Reutilización de la PKI para múltiples servicios institucionales.

### Negativas / Trade-offs

- Mayor coordinación entre equipos/repositorios.
- Necesidad de mantener contratos de integración explícitos.
- Documentación transversal adicional para onboarding.

---

## Límites explícitos en `upeu-mothership-radius`

No se aceptan en este repositorio:

- Scripts de instalación, bootstrap o hardening de CA/RA/OCSP.
- Material criptográfico sensible (private keys, backups de CA, tokens HSM, secretos).
- Procedimientos internos de continuidad/recuperación específicos de PKI.

Sí se aceptan:

- Diagramas y flujos de integración FreeRADIUS ↔ PKI ↔ Intune/Entra.
- Requisitos de interfaz necesarios para autenticación EAP-TLS.
- Referencias versionadas hacia repositorios PKI oficiales.

---

## Referencias

- Repositorio RADIUS: `upeu-mothership-radius`
- Repositorio de arquitectura PKI: `upeu-pki-architecture`
- Repositorio de implementación PKI: `upeu-ejbca-pki`

