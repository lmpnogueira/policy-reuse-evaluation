# Evaluation Dataset

> This document catalogues every Kubernetes manifest used to evaluate the
> Policy-as-Code proof of concept. It is intended to provide the traceability
> and methodological transparency expected of a master's dissertation.

---

## 1. Terminology

| Term | Definition |
|---|---|
| **Valid baseline** | A manifest that satisfies all five policies. Used to confirm that the enforcement tooling does not produce false positives on compliant workloads. |
| **Single-policy violation** | A manifest that violates exactly one policy while satisfying all others. Used to verify that each policy can be triggered in isolation. |
| **Multi-policy violation** | A manifest that violates two or more policies simultaneously. Used to verify concurrent detection, per-container iteration, or cross-resource-type enforcement. |
| **Non-target resource** | A Kubernetes resource whose kind falls outside the policies' evaluation path (`spec.template.spec.containers`). Used as a negative control to confirm zero false positives on structurally inapplicable inputs. |
| **CI bypass scenario** | A manifest applied directly to the cluster via `kubectl apply --dry-run=server`, bypassing the CI pipeline entirely. Used to validate the defence-in-depth property of Gatekeeper admission control. |

### Origin Labels

All manifests in this dataset were authored specifically for the PoC evaluation.
To characterise how closely each manifest resembles a production artifact, the
following labels are used:

| Label | Meaning |
|---|---|
| **Synthetic** | Purpose-built to trigger or avoid a specific policy. Structure is minimal and exists solely to exercise the policy engine. |
| **Adapted realistic** | Modelled on a realistic workload pattern (e.g.\ database StatefulSet, migration Job, sidecar Deployment) but authored for this evaluation rather than extracted from a live system. |
| **Realistic** | Represents a plausible production resource (e.g.\ ConfigMap with database connection strings, ClusterIP Service). Contains no deliberate policy-relevant fields because the resource kind is outside policy scope. |

---

## 2. Policy Reference

The dataset is evaluated against five policies (P1--P5) encoded as nine Rego
deny rules. All policies iterate over `input.spec.template.spec.containers[_]`.

| ID | Policy | Rego File | Deny Rules | Gatekeeper |
|---|---|---|---|---|
| P1 | Containers must not run as root | `no-root.rego` | 1 | Yes |
| P2 | Privilege escalation must be disabled | `no-priv-escalation.rego` | 1 | Yes |
| P3 | CPU/memory requests and limits required | `resource-limits.rego` | 4 | No |
| P4 | Images must not use `:latest` or omit a tag | `no-latest-tag.rego` | 2 | Yes |
| P5 | Containers must not run in privileged mode | `no-privileged.rego` | 1 | No |

---

## 3. Complete Manifest Catalogue

### 3.1 Valid Baselines (9 manifests)

| ID | File | Resource | Origin | Expected CI | Expected Admission | Violated Policies | Notes |
|---|---|---|---|---|---|---|---|
| D-01 | `tests/good/deployment-good.yaml` | Deployment | Synthetic | PASS | ALLOWED | None | Reference manifest; all 5 policies explicitly satisfied (nginx:1.25.3) |
| D-02 | `tests/good/deployment-minimal.yaml` | Deployment | Synthetic | PASS | -- | None | Minimal viable compliant spec; lowest resource values that still satisfy P3 (alpine:3.19) |
| D-03 | `tests/good/deployment-multi-container.yaml` | Deployment | Adapted realistic | PASS | -- | None | Two containers (Python API + busybox sidecar); verifies both are evaluated independently |
| D-04 | `tests/good/statefulset-good.yaml` | StatefulSet | Adapted realistic | PASS | -- | None | Database workload (postgres:16.2); confirms `spec.template` path applies to StatefulSets |
| D-05 | `tests/good/job-good.yaml` | Job | Adapted realistic | PASS | -- | None | Batch migration workload (flyway:10.8); confirms `spec.template` path applies to Jobs |
| D-30 | `tests/good/deployment-no-privileged-field.yaml` | Deployment | Synthetic | PASS | -- | None | `privileged` field omitted entirely (not set to `false`); proves P5 does not treat absence as `true` |
| D-31 | `tests/good/deployment-sha-digest.yaml` | Deployment | Synthetic | PASS | -- | None | Image referenced by digest (`nginx@sha256:...`); proves P4 handles digest references without false-positive |
| D-32 | `tests/good/deployment-extra-security-fields.yaml` | Deployment | Synthetic | PASS | -- | None | Hardened `securityContext` with extra fields (`readOnlyRootFilesystem`, `capabilities.drop`, `runAsUser`); proves `object.get` is unaffected by additional keys |
| D-34 | `tests/good/deployment-init-container.yaml` | Deployment | Synthetic | PASS | -- | None | Init container (`busybox`, no tag, no `securityContext`) + compliant app container; proves policies scope to `containers[_]` only, not `initContainers` |

### 3.2 Single-Policy Violations (9 manifests)

Each manifest violates exactly one policy. All other policies are satisfied.

| ID | File | Resource | Origin | Expected CI | Expected Admission | Violated Policies | Notes |
|---|---|---|---|---|---|---|---|
| D-06 | `tests/bad/deployment-root.yaml` | Deployment | Synthetic | FAIL (1) | REJECTED | P1 | `runAsNonRoot: false`; all other policies satisfied |
| D-07 | `tests/bad/deployment-priv-escalation.yaml` | Deployment | Synthetic | FAIL (1) | REJECTED | P2 | `allowPrivilegeEscalation: true`; all other policies satisfied |
| D-08 | `tests/bad/deployment-no-resources.yaml` | Deployment | Synthetic | FAIL (4) | -- | P3 | Entire `resources` block absent; all 4 P3 deny rules fire |
| D-09 | `tests/bad/deployment-latest-tag.yaml` | Deployment | Synthetic | FAIL (1) | REJECTED | P4 | `image: nginx:latest`; triggers the `:latest` suffix rule |
| D-10 | `tests/bad/deployment-privileged.yaml` | Deployment | Synthetic | FAIL (1) | -- | P5 | `privileged: true`; all other policies satisfied |
| D-11 | `tests/bad/deployment-no-tag.yaml` | Deployment | Synthetic | FAIL (1) | -- | P4 | `image: nginx` (no colon); triggers the missing-tag rule |
| D-12 | `tests/bad/deployment-partial-resources.yaml` | Deployment | Synthetic | FAIL (2) | -- | P3 | Has `requests` but no `limits`; 2 of 4 P3 rules fire |
| D-16 | `tests/bad/deployment-second-container-violation.yaml` | Deployment | Adapted realistic | FAIL (1) | -- | P4 | 1st container compliant; 2nd container (`fluentd:latest`) violates P4. Tests per-container iteration |
| D-17 | `tests/bad/statefulset-latest-tag.yaml` | StatefulSet | Adapted realistic | FAIL (1) | -- | P4 | `:latest` tag on a StatefulSet (redis:latest); cross-resource-type test |

> D-08 produces 4 failures because P3 contains four independent deny rules. D-12 produces 2 failures (only the `limits` rules fire, since `requests` are present).

### 3.3 Multi-Policy Violations (6 manifests)

Each manifest violates two or more policies simultaneously.

| ID | File | Resource | Origin | Expected CI | Expected Admission | Violated Policies | Notes |
|---|---|---|---|---|---|---|---|
| D-13 | `tests/bad/deployment-no-security-context.yaml` | Deployment | Adapted realistic | FAIL (2) | -- | P1, P2 | `securityContext` omitted entirely; `object.get` defaults trigger both P1 and P2 |
| D-14 | `tests/bad/deployment-root-and-escalation.yaml` | Deployment | Synthetic | FAIL (2) | -- | P1, P2 | Both security fields set to insecure values explicitly |
| D-15 | `tests/bad/deployment-three-violations.yaml` | Deployment | Synthetic | FAIL (3) | -- | P1, P2, P4 | Root + escalation + `:latest` tag in a single container |
| D-18 | `tests/bad/deployment-multi-container-mixed.yaml` | Deployment | Adapted realistic | FAIL (6) | -- | P1, P3, P4 | 1st container compliant; sidecar violates P1 + P3 (x4) + P4 (no tag) |
| D-19 | `tests/bad/job-multi-violation.yaml` | Job | Adapted realistic | FAIL (6) | -- | P1, P3, P4 | Job resource: root + `:latest` + no resources block |
| D-20 | `tests/bad/deployment-multi-violation.yaml` | Deployment | Synthetic | FAIL (8) | REJECTED | P1--P5 | Maximum-violation reference; all 5 policies violated simultaneously |

### 3.4 Non-Target Resources — Negative Controls (5 manifests)

| ID | File | Resource | Origin | Expected CI | Expected Admission | Violated Policies | Notes |
|---|---|---|---|---|---|---|---|
| D-21 | `tests/good/configmap.yaml` | ConfigMap | Realistic | PASS | -- | None | Application configuration data; no container spec exists |
| D-22 | `tests/good/service.yaml` | Service | Realistic | PASS | -- | None | ClusterIP Service; no container spec exists |
| D-23 | `tests/good/namespace.yaml` | Namespace | Realistic | PASS | -- | None | Cluster-level resource; no pod template |
| D-24 | `tests/good/pod-negative-control.yaml` | Pod (bare) | Synthetic | PASS | -- | None | Uses `spec.containers` not `spec.template.spec.containers`; intentionally uses `busybox:latest` with no `securityContext` to document the known scope limitation |
| D-33 | `tests/good/cronjob-good.yaml` | CronJob | Synthetic | PASS | -- | None | Uses `spec.jobTemplate.spec.template.spec.containers`; intentionally uses `busybox:latest` to document a second scope boundary — policies only reach `spec.template.spec.containers` |

---

## 4. CI Bypass Scenarios — Gatekeeper Admission Control

These are not separate manifest files. They re-use existing manifests (D-01,
D-06, D-07, D-09, D-20) applied directly to the cluster with
`kubectl apply --dry-run=server`, bypassing the CI pipeline entirely.

Gatekeeper enforces P1, P2, and P4 only. P3 and P5 are CI-only in this PoC.

| ID | Manifest Reused | Policies Enforced | Expected Admission | Actual Admission |
|---|---|---|---|---|
| D-25 | D-01 (`deployment-good.yaml`) | -- | ALLOWED | **ALLOWED** |
| D-26 | D-06 (`deployment-root.yaml`) | P1 | REJECTED | **REJECTED** |
| D-27 | D-07 (`deployment-priv-escalation.yaml`) | P2 | REJECTED | **REJECTED** |
| D-28 | D-09 (`deployment-latest-tag.yaml`) | P4 | REJECTED | **REJECTED** |
| D-29 | D-20 (`deployment-multi-violation.yaml`) | P1, P2, P4 | REJECTED | **REJECTED** |

---

## 5. Dataset Composition Summary

### 5.1 By Category

| Category | Count | Percentage |
|---|---|---|
| Valid baseline | 9 | 31.0% |
| Single-policy violation | 9 | 31.0% |
| Multi-policy violation | 6 | 20.7% |
| Non-target resource | 5 | 17.2% |
| **Total (unique manifests)** | **29** | **100%** |

### 5.2 By Resource Type

| Resource Type | Good | Bad | Total |
|---|---|---|---|
| Deployment | 7 | 12 | 19 |
| StatefulSet | 1 | 1 | 2 |
| Job | 1 | 1 | 2 |
| CronJob | 1 | 0 | 1 |
| ConfigMap | 1 | 0 | 1 |
| Service | 1 | 0 | 1 |
| Namespace | 1 | 0 | 1 |
| Pod (bare) | 1 | 0 | 1 |
| **Total** | **14** | **15** | **29** |

### 5.3 By Origin

| Origin | Count | Percentage |
|---|---|---|
| Synthetic | 18 | 62.1% |
| Adapted realistic | 8 | 27.6% |
| Realistic | 3 | 10.3% |
| **Total** | **29** | **100%** |

### 5.4 Policy Coverage

Each policy is triggered by at least two bad manifests, ensuring no policy
depends on a single test case for coverage.

| Policy | Triggered By (Single) | Triggered By (Multi) | Total Triggers |
|---|---|---|---|
| P1 | D-06 | D-13, D-14, D-15, D-18, D-19, D-20 | 7 |
| P2 | D-07 | D-13, D-14, D-15, D-20 | 5 |
| P3 | D-08, D-12 | D-18, D-19, D-20 | 5 |
| P4 | D-09, D-11, D-16, D-17 | D-15, D-18, D-19, D-20 | 8 |
| P5 | D-10 | D-20 | 2 |

---

## 6. Verified Test Results

These totals are taken from the Conftest log
`results/logs/conftest-test-20260415-111740.log`.

| Metric | Value |
|---|---|
| Total manifests | 29 |
| Total assertions (9 rules x manifests) | 261 |
| Assertions passed | 221 |
| Violations detected | 40 |
| False positives | 0 |
| False negatives | 0 |
| Admission tests (Gatekeeper) | 5 |
| Admission outcomes matched | 5 / 5 |

---

## 7. Classification Rationale

The dataset was designed around five principles that strengthen the evaluation's
defensibility in a dissertation context:

### 7.1 Per-Policy Isolation

Every policy has at least one dedicated single-violation manifest (D-06 through
D-12) where only that policy's deny rule fires. This isolates the policy logic
and confirms that a FAIL result is attributable to the intended rule, not to an
interaction with another rule.

### 7.2 Concurrent Violation

Multi-violation manifests (D-14 through D-20) demonstrate that the policy engine
correctly reports all applicable violations in a single evaluation pass. D-20
is the maximum-violation reference: all five policies fire, producing eight
deny messages.

### 7.3 Structural Variation

The dataset exercises three structural dimensions beyond the baseline Deployment:

| Dimension | Manifests | What It Tests |
|---|---|---|
| Multi-container pods | D-03, D-16, D-18 | Per-container iteration (`containers[_]`) |
| Init containers | D-34 | Policies scope to `containers[_]` only, not `initContainers` |
| Non-Deployment workloads | D-04, D-05, D-17, D-19 | StatefulSet and Job share `spec.template.spec.containers` |
| Omitted vs. explicit fields | D-12, D-13, D-14, D-30 | `object.get` defaults (D-13) vs. partial fields (D-12) vs. explicit insecure values (D-14) vs. omitted `privileged` (D-30) |
| Image reference formats | D-31 | Digest-based reference (`@sha256:...`) not confused with tag-based |
| Hardened securityContext | D-32 | Extra fields (`readOnlyRootFilesystem`, `capabilities.drop`) do not interfere with `object.get` evaluation |

### 7.4 Negative Controls

Five non-target resources (D-21 through D-24, D-33) confirm that the policy set does
not over-match. D-24 (bare Pod with `busybox:latest` and no `securityContext`)
is particularly important: it documents the known scope limitation that bare
Pods are not covered by policies that iterate over `spec.template.spec.containers`.
D-33 (CronJob with `busybox:latest`) documents a second scope boundary:
CronJobs nest containers at `spec.jobTemplate.spec.template.spec.containers`,
which is one level deeper than the path evaluated by the policies.

### 7.5 Defence-in-Depth Validation

The CI bypass scenarios (D-25 through D-29) validate the second enforcement
point. They reuse existing manifests rather than introducing new ones, ensuring
that the admission results are directly comparable to the CI results for the
same input.

---

## 8. Known Limitations

| Limitation | Impact | Documented In |
|---|---|---|
| All policies use `spec.template.spec.containers`; bare Pods and CronJobs are not evaluated | A bare Pod or CronJob with `:latest` or root passes all policies | D-24, D-33, `docs/scope.md` |
| P3 and P5 have no Gatekeeper ConstraintTemplates | These policies are enforced at CI only; admission bypass is not blocked for P3/P5 violations | Section 4 |
| All manifests are synthetic or adapted; none are extracted from live production clusters | Limits generalisability claims to the PoC scope | Section 5.3 |
| Dataset covers 8 resource types but only 3 (Deployment, StatefulSet, Job) have `spec.template` and are therefore policy-relevant | CronJob and DaemonSet use different nesting paths; CronJob is documented as a negative control (D-33) | Section 5.2 |
| Policies iterate `containers[_]` only; `initContainers` are not evaluated | An init container with `:latest` or root passes all policies | D-34 |
