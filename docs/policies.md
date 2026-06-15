# Policy Catalogue

> **Tooling:** Conftest 0.67.1 (OPA 1.14.1) · Rego v1 syntax (`import rego.v1`)
> **Policy path:** `policies/kubernetes/`

---

## P1 — Containers Must Not Run as Root

| Field | Value |
|---|---|
| **File** | `policies/kubernetes/no-root.rego` |
| **Rule** | `deny contains msg if { ... not sc.runAsNonRoot == true ... }` |
| **Severity** | High |
| **Enforcement** | CI validation (Conftest) · Admission control (Gatekeeper) |

### Statement
All containers must be configured to run as non-root users.

### Rationale
Running containers as root increases the impact of container escape, privilege abuse, and host-level compromise.

### Compliant Example
```yaml
securityContext:
  runAsNonRoot: true
```

### Violation Example
```yaml
securityContext:
  runAsNonRoot: false
```

---

## P2 — Privilege Escalation Must Be Disabled

| Field | Value |
|---|---|
| **File** | `policies/kubernetes/no-priv-escalation.rego` |
| **Rule** | `deny contains msg if { ... not sc.allowPrivilegeEscalation == false ... }` |
| **Severity** | High |
| **Enforcement** | CI validation (Conftest) · Admission control (Gatekeeper) |

### Statement
All containers must explicitly disable privilege escalation.

### Rationale
Privilege escalation allows processes to gain higher privileges than intended, increasing attack surface and risk.

### Compliant Example
```yaml
securityContext:
  allowPrivilegeEscalation: false
```

### Violation Example
```yaml
securityContext:
  allowPrivilegeEscalation: true
```

---

## P3 — Resource Requests and Limits Must Be Defined

| Field | Value |
|---|---|
| **File** | `policies/kubernetes/resource-limits.rego` |
| **Rules** | 4 deny rules (requests.cpu, requests.memory, limits.cpu, limits.memory) |
| **Severity** | Medium |
| **Enforcement** | CI validation (Conftest) |

### Statement
All containers must define CPU and memory requests and limits.

### Rationale
Missing resource constraints can cause resource starvation, noisy-neighbor issues, and unstable cluster behavior.

### Compliant Example
```yaml
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "256Mi"
```

### Violation Example
```yaml
# No resources block defined
```

---

## P4 — Container Images Must Not Use the `latest` Tag

| Field | Value |
|---|---|
| **File** | `policies/kubernetes/no-latest-tag.rego` |
| **Rules** | 2 deny rules (`:latest` suffix and missing tag) |
| **Severity** | Medium |
| **Enforcement** | CI validation (Conftest) · Admission control (Gatekeeper) |

### Statement
Container images must not use the mutable `latest` tag.

### Rationale
The `latest` tag reduces traceability, reproducibility, and deployment predictability.

### Compliant Example
```yaml
image: nginx:1.25.3
```

### Violation Example
```yaml
image: nginx:latest
```

---

## P5 — Privileged Containers Are Forbidden

| Field | Value |
|---|---|
| **File** | `policies/kubernetes/no-privileged.rego` |
| **Rule** | `deny contains msg if { ... sc.privileged == true ... }` |
| **Severity** | Critical |
| **Enforcement** | CI validation (Conftest) |

### Statement
Containers must not run in privileged mode.

### Rationale
Privileged containers have broad access to host resources and significantly weaken isolation guarantees.

### Compliant Example
```yaml
securityContext:
  privileged: false
```

### Violation Example
```yaml
securityContext:
  privileged: true
```

---

## Rego Syntax Note

All policies use **OPA v1 / Rego v1** syntax, which requires:

```rego
import rego.v1

deny contains msg if {
  # rule body
}
```

This replaces the legacy `deny[msg] { ... }` form used in OPA v0.x. The migration was required by Conftest 0.67.1 (OPA 1.14.1), which enforces OPA v1 grammar by default.