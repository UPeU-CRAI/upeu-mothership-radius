# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repository Is

**Pure documentation repo.** There is no application code, build system, or test suite. The placeholder directories (`freeradius/`, `infrastructure/`, `intune/`) contain only `.gitkeep` files pending future IaC/config work. All substantive content lives in `docs/`.

## Architecture Being Documented

The UPeU Wi-Fi authentication stack follows the **InkBridge Networks Mothership-Satellite model**:

- **MOTHERSHIP-AWS** (`54.166.108.154`) — FreeRADIUS 3.2.x on Ubuntu 24.04 EC2. Sole decision-maker: validates EAP-TLS certificates against Microsoft Cloud PKI, issues Access-Accept/Reject, centralizes audit logging (`auth = yes`).
- **SAT-LIMA-01** (`192.168.62.89`) — FreeRADIUS 3.2.x on Ubuntu 24.04 VMware. **Proxy pure**: forwards all auth to Mothership, caches reply attributes (VLAN, Reply-Message) for resilience only. Does **not** validate certificates. Does **not** log auth (`auth = no`).
- **Access Points** (`172.16.79.0/24`) — Ubiquiti UniFi, send RADIUS to local Satellite.
- **Microsoft Cloud PKI + Intune** — Issues x.509 certs (SCEP) to devices; FreeRADIUS trusts the `ca-root.pem` downloaded from Cloud PKI.

Authentication is **EAP-TLS only** (Zero Trust). PEAP/MSCHAPv2 are intentionally disabled.

## Documentation Structure

| Directory | Covers |
|---|---|
| `docs/01-arquitectura/` | End-to-end flow diagram and component glossary |
| `docs/02-mothership-aws/` | EC2 setup (`despliegue-instancia.md`) and full RADIUS config (`configuracion-radius.md`) — EAP-TLS, TLS cache, thread pool, logging |
| `docs/03-satellites-locales/` | Ubuntu install (`instalacion-ubuntu.md`) and proxy config (`configuracion-proxy.md`) — proxy.conf, clients.conf, attribute cache |
| `docs/04-identidad-y-pki/` | Entra ID integration, Cloud PKI hierarchy, Intune SCEP/Wi-Fi profiles |
| `docs/05-operaciones/` | Monitoring/log commands, maintenance runbook |
| `docs/06-troubleshooting/` | Symptom → root cause → fix for the 8 most common failure modes |

## Established Conventions

### Versions and Paths
- Software version: **FreeRADIUS 3.2.x** (3.2.5 on Ubuntu 24.04). The package installs to `/etc/freeradius/3.0/` — this path is correct and must not be changed.
- OS: **Ubuntu 24.04 LTS** on both Mothership (EC2) and Satellites (VMware).

### Security Baseline (non-negotiable)
Every `client {}` block in any `clients.conf` — whether documenting APs or Satellites — must include both:
```ini
require_message_authenticator = yes   # CVE-2024-3596 (BLASTRADIUS)
limit_proxy_state = yes               # Proxy-State abuse mitigation
```
The corresponding `[!IMPORTANT]` callout must reference **CVE-2024-3596** by name.

### Key Config Values (already decided)
| Parameter | Value | Location |
|---|---|---|
| `tls_min_version` | `"1.2"` | Mothership `mods-available/eap` |
| `tls_max_version` | *(not set — allows TLS 1.3)* | Mothership `mods-available/eap` |
| `cipher_list` | `"ECDHE+AESGCM:ECDHE+CHACHA20:!aNULL:!MD5:!DSS"` | Mothership `mods-available/eap` |
| TLS cache `max_entries` | `1024` | Mothership `mods-available/eap` |
| Attribute cache `max_entries` | `2000` | Satellite `mods-available/cache` |
| `zombie_period` | `40` | Satellite `proxy.conf` |
| `status_check` | `status-server` | Satellite `proxy.conf` |
| `default_fallback` | `no` | Satellite `proxy.conf` (`proxy server {}` block) |
| `min_spare_servers` | `15` | Mothership `radiusd.conf` |

### Document Header Convention
Every doc must open with a blockquote header containing **Rol**, **Referencia**, and cross-links to related docs:
```markdown
> **Rol:** <one-line description of what this server/component does>
> **Referencia:** [InkBridge Networks — RADIUS for Universities](https://www.inkbridgenetworks.com/blog/blog-10/radius-for-universities-122)
> **Versión:** FreeRADIUS 3.2.x sobre Ubuntu 24.04 LTS
```

### Writing Style
- **Placeholders** use `<UPPER_SNAKE_CASE>` angle brackets (e.g., `<SHARED_SECRET_UPEU>`, `<IP_ELASTICA_MOTHERSHIP>`). Never use real IPs or secrets in docs.
- **Callouts** use GitHub-flavored `> [!NOTE/TIP/IMPORTANT/WARNING/CAUTION]`. Use `[!IMPORTANT]` for security-critical items, `[!CAUTION]` for destructive/irreversible operations.
- **Diagrams** use Mermaid (`flowchart`, `sequenceDiagram`, `gantt`). Every major concept has a diagram.
- **Language**: Spanish throughout. Technical terms (EAP-TLS, RADIUS, proxy, cache, thread pool) are kept in English.
- **Reference standard**: Cite [InkBridge Networks](https://www.inkbridgenetworks.com/blog/blog-10/radius-for-universities-122) when establishing design decisions.
