# azure-platform-demos

A **monorepo** of demos for the **Azure Platform**. Each demo is a
self-contained project — with its own infrastructure-as-code, deployment
scripts, dashboards, and documentation — showcasing a specific Azure
capability, service, or architecture pattern.

Additional demos will be added over time; each lives in its own top-level
directory with a dedicated README.

---

## Demos

| Demo | Description |
| --- | --- |
| [anf-attestation](anf-attestation/README.md) | Windows Server → Azure NetApp Files migration with cryptographically verifiable, SHA-256-based file attestation. Deployed with Bicep. |

---

## Repository Structure

```
azure-platform-demos/
├── README.md              ← This file (monorepo overview)
├── LICENSE
└── anf-attestation/       ← Attestation demo (Windows Server → Azure NetApp Files)
```

Each demo directory is independent — refer to its own README for
architecture, prerequisites, and deployment instructions.
