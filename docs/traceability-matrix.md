# Traceability Matrix

> **CI results:** Conftest 0.67.1 (OPA 1.14.1). Log: `results/logs/conftest-test-20260415-111740.log`
> **Admission results:** Gatekeeper 3.18.0 on kind (K8s 1.32). Log: `results/logs/gatekeeper-test-20260325-152857.log`
> **Dataset:** 29 manifests (9 compliant + 5 negative-control + 9 single-violation + 6 multi-violation), 5 policies, 9 deny rules.

---

## Policy → Rego File Mapping

| Policy | Description | Rego File | Deny Rules |
|---|---|---|---|
| P1 | Containers must not run as root | `no-root.rego` | 1 |
| P2 | Privilege escalation must be disabled | `no-priv-escalation.rego` | 1 |
| P3 | CPU/memory requests and limits must be defined | `resource-limits.rego` | 4 |
| P4 | Images must not use the `:latest` tag | `no-latest-tag.rego` | 2 |
| P5 | Containers must not run in privileged mode | `no-privileged.rego` | 1 |
| | | **Total** | **9** |

---

## Original Scenario → Manifest → Policy Mapping (S1-S8)

| Scenario | Manifest File | Violates | CI Expected | CI Actual | CI Failures | Admission Expected | Admission Actual |
|---|---|---|---|---|---|---|---|
| S1 | `tests/good/deployment-good.yaml` | — | PASS | **PASS** | 0 | ALLOWED | **ALLOWED** |
| S2 | `tests/bad/deployment-root.yaml` | P1 | FAIL | **FAIL** | 1 | REJECTED | **REJECTED** |
| S3 | `tests/bad/deployment-priv-escalation.yaml` | P2 | FAIL | **FAIL** | 1 | REJECTED | **REJECTED** |
| S4 | `tests/bad/deployment-no-resources.yaml` | P3 | FAIL | **FAIL** | 4 | — | — |
| S5 | `tests/bad/deployment-latest-tag.yaml` | P4 | FAIL | **FAIL** | 1 | REJECTED | **REJECTED** |
| S6 | `tests/bad/deployment-privileged.yaml` | P5 | FAIL | **FAIL** | 1 | — | — |
| S7 | `tests/bad/deployment-multi-violation.yaml` | P1-P5 | FAIL | **FAIL** | 8 | REJECTED | **REJECTED** |
| S8 | (bypass CI, apply directly) | P1,P2,P4 | — | — | — | REJECTED | **REJECTED** |

> S4 and S6 are not tested at admission because P3 (resource limits) and P5 (privileged mode) were not implemented as Gatekeeper constraints in this PoC.

---

## Extended Dataset — Good Manifests (CI Only)

| ID | Manifest File | Resource Type | Key Characteristic | CI Result | Failures |
|---|---|---|---|---|---|
| D-01 | `tests/good/deployment-good.yaml` | Deployment | Single container, all policies satisfied | **PASS** | 0 |
| D-02 | `tests/good/deployment-minimal.yaml` | Deployment | Minimal compliant spec (alpine:3.19) | **PASS** | 0 |
| D-03 | `tests/good/deployment-multi-container.yaml` | Deployment | 2 containers (api + sidecar), both compliant | **PASS** | 0 |
| D-04 | `tests/good/statefulset-good.yaml` | StatefulSet | postgres:16.2, stateful workload | **PASS** | 0 |
| D-05 | `tests/good/job-good.yaml` | Job | flyway:10.8, batch workload | **PASS** | 0 |
| D-30 | `tests/good/deployment-no-privileged-field.yaml` | Deployment | `privileged` field omitted entirely; P5 treats absence correctly | **PASS** | 0 |
| D-31 | `tests/good/deployment-sha-digest.yaml` | Deployment | Image by digest (`nginx@sha256:...`); P4 handles digests | **PASS** | 0 |
| D-32 | `tests/good/deployment-extra-security-fields.yaml` | Deployment | Hardened `securityContext` with extra fields | **PASS** | 0 |
| D-34 | `tests/good/deployment-init-container.yaml` | Deployment | Init container (no tag, no securityContext) + compliant app | **PASS** | 0 |

## Extended Dataset — Negative Controls (CI Only)

| ID | Manifest File | Resource Type | Why It Passes | CI Result | Failures |
|---|---|---|---|---|---|
| D-21 | `tests/good/configmap.yaml` | ConfigMap | No container spec | **PASS** | 0 |
| D-22 | `tests/good/service.yaml` | Service | No container spec | **PASS** | 0 |
| D-23 | `tests/good/namespace.yaml` | Namespace | Cluster-level resource | **PASS** | 0 |
| D-24 | `tests/good/pod-negative-control.yaml` | Pod (bare) | `spec.containers` ≠ `spec.template.spec.containers` | **PASS** | 0 |
| D-33 | `tests/good/cronjob-good.yaml` | CronJob | `spec.jobTemplate.spec.template.spec.containers` (one level deeper) | **PASS** | 0 |

## Extended Dataset — Bad Manifests — Single-Policy Violations (CI Only)

| ID | Manifest File | Resource Type | Violated Policies | CI Result | Failures |
|---|---|---|---|---|---|
| D-06 | `tests/bad/deployment-root.yaml` | Deployment | P1 | **FAIL** | 1 |
| D-07 | `tests/bad/deployment-priv-escalation.yaml` | Deployment | P2 | **FAIL** | 1 |
| D-08 | `tests/bad/deployment-no-resources.yaml` | Deployment | P3 | **FAIL** | 4 |
| D-09 | `tests/bad/deployment-latest-tag.yaml` | Deployment | P4 | **FAIL** | 1 |
| D-10 | `tests/bad/deployment-privileged.yaml` | Deployment | P5 | **FAIL** | 1 |
| D-11 | `tests/bad/deployment-no-tag.yaml` | Deployment | P4 (no tag) | **FAIL** | 1 |
| D-12 | `tests/bad/deployment-partial-resources.yaml` | Deployment | P3 (partial) | **FAIL** | 2 |
| D-16 | `tests/bad/deployment-second-container-violation.yaml` | Deployment | P4 (2nd container) | **FAIL** | 1 |
| D-17 | `tests/bad/statefulset-latest-tag.yaml` | StatefulSet | P4 | **FAIL** | 1 |

## Extended Dataset — Bad Manifests — Multi-Policy Violations (CI Only)

| ID | Manifest File | Resource Type | Violated Policies | CI Result | Failures |
|---|---|---|---|---|---|
| D-13 | `tests/bad/deployment-no-security-context.yaml` | Deployment | P1 + P2 | **FAIL** | 2 |
| D-14 | `tests/bad/deployment-root-and-escalation.yaml` | Deployment | P1 + P2 | **FAIL** | 2 |
| D-15 | `tests/bad/deployment-three-violations.yaml` | Deployment | P1 + P2 + P4 | **FAIL** | 3 |
| D-18 | `tests/bad/deployment-multi-container-mixed.yaml` | Deployment | P1 + P3 + P4 (sidecar) | **FAIL** | 6 |
| D-19 | `tests/bad/job-multi-violation.yaml` | Job | P1 + P3 + P4 | **FAIL** | 6 |
| D-20 | `tests/bad/deployment-multi-violation.yaml` | Deployment | P1-P5 | **FAIL** | 8 |

---

## Policy × Scenario Coverage Matrix (CI - Conftest, Original S1-S7)

Each cell shows whether the policy was **triggered** (✗ = violation detected) or **passed** (✓) for that scenario.

| Policy | S1 (good) | S2 (root) | S3 (escalation) | S4 (resources) | S5 (latest) | S6 (privileged) | S7 (multi) |
|---|---|---|---|---|---|---|---|
| P1 | ✓ | **✗** | ✓ | ✓ | ✓ | ✓ | **✗** |
| P2 | ✓ | ✓ | **✗** | ✓ | ✓ | ✓ | **✗** |
| P3 | ✓ | ✓ | ✓ | **✗ ×4** | ✓ | ✓ | **✗ ×4** |
| P4 | ✓ | ✓ | ✓ | ✓ | **✗** | ✓ | **✗** |
| P5 | ✓ | ✓ | ✓ | ✓ | ✓ | **✗** | **✗** |

**CI Coverage:** All 5 policies are exercised by at least one dedicated bad manifest (S2-S6) and collectively by S7.

---

## Policy × Extended Bad Manifest Coverage (CI - Conftest)

| Policy | D-11 (no tag) | D-12 (partial res) | D-13 (no secCtx) | D-16 (2nd ctr) | D-17 (SS latest) | D-14 (root+esc) | D-15 (3 viol) | D-18 (mixed ctr) | D-19 (job multi) |
|---|---|---|---|---|---|---|---|---|---|
| P1 | ✓ | ✓ | **✗** | ✓ | ✓ | **✗** | **✗** | **✗** | **✗** |
| P2 | ✓ | ✓ | **✗** | ✓ | ✓ | **✗** | **✗** | ✓ | ✓ |
| P3 | ✓ | **✗ ×2** | ✓ | ✓ | ✓ | ✓ | ✓ | **✗ ×4** | **✗ ×4** |
| P4 | **✗** | ✓ | ✓ | **✗** | **✗** | ✓ | **✗** | **✗** | **✗** |
| P5 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

**Extended coverage highlights:**
- P3 tested in partial mode (D-12: requests without limits → 2 failures) in addition to complete absence (D-08/S4: 4 failures)
- P4 tested with missing tag (D-11), second container (D-16), and StatefulSet (D-17) in addition to `:latest` (D-09/S5)
- P1+P2 tested via omitted securityContext (D-13), explicit insecure values (D-14), and multi-container (D-18)
- Job workloads tested (D-19)

---

## Policy × Scenario Coverage Matrix (Admission - Gatekeeper)

Gatekeeper enforces 3 of the 5 policies (P1, P2, P4) at the Kubernetes API server level. Testing uses `kubectl apply --dry-run=server`.

| Policy | S1 (good) | S2 (root) | S3 (escalation) | S5 (latest) | S7 (multi) |
|---|---|---|---|---|---|
| P1 | ✓ | **✗** | ✓ | ✓ | **✗** |
| P2 | ✓ | ✓ | **✗** | ✓ | **✗** |
| P4 | ✓ | ✓ | ✓ | **✗** | **✗** |

**Admission Coverage:** All 3 Gatekeeper policies triggered by dedicated bad manifests and collectively by S7 (multi-violation).

---

## Detailed Violation Messages (S7 — Multi-Violation)

| # | Policy | Conftest Message |
|---|---|---|
| 1 | P1 | Container 'app' must set securityContext.runAsNonRoot to true |
| 2 | P2 | Container 'app' must set securityContext.allowPrivilegeEscalation to false |
| 3 | P3 | Container 'app' must define resources.requests.cpu |
| 4 | P3 | Container 'app' must define resources.requests.memory |
| 5 | P3 | Container 'app' must define resources.limits.cpu |
| 6 | P3 | Container 'app' must define resources.limits.memory |
| 7 | P4 | Container 'app' uses image 'nginx:latest' with ':latest' tag — use a pinned version instead |
| 8 | P5 | Container 'app' must not run in privileged mode |

---

## Summary

### CI Enforcement (Conftest) — Full Dataset

| Metric | Value |
|---|---|
| Total policies | 5 |
| Total deny rules | 9 |
| Good manifests (compliant workloads) | 9 |
| Good manifests (negative controls) | 5 |
| Bad manifests (single-violation) | 9 |
| Bad manifests (multi-violation) | 6 |
| **Total manifests** | **29** |
| Total test assertions | 261 |
| Assertions passed | 221 |
| Violations detected | 40 |
| False positives | 0 |
| False negatives | 0 |
| Policy coverage | 100% (all 5 policies triggered) |
| Resource types tested | 8 (Deployment, StatefulSet, Job, CronJob, ConfigMap, Service, Namespace, Pod) |

### Admission Enforcement (Gatekeeper)

| Metric | Value |
|---|---|
| Gatekeeper version | 3.18.0 |
| Policies enforced at admission | 3 (P1, P2, P4) |
| ConstraintTemplates | 3 |
| Constraints | 3 |
| Total admission tests | 5 |
| Good manifests tested | 1 |
| Bad manifests tested | 4 |
| Expected results | 5 / 5 |
| Unexpected results | 0 |
| Admission policy coverage | 100% (all 3 Gatekeeper policies triggered) |

### Combined Enforcement

| Metric | Value |
|---|---|
| Total enforcement points | 2 (CI + Admission) |
| Total policies | 5 (CI: 5, Admission: 3) |
| Total manifests evaluated | 29 (CI) + 5 (Admission) |
| All tests passed | Yes |
| S25–S29 (CI bypass) blocked by Gatekeeper | Yes (for P1, P2, P4) |
