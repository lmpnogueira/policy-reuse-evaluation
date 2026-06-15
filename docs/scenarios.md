# Scenario Matrix

> **CI enforcement:** Conftest 0.67.1 (OPA 1.14.1). Script: `scripts/conftest-test.ps1`. Log: `results/logs/conftest-test-20260415-111740.log`
> **Admission enforcement:** OPA Gatekeeper 3.18.0 on kind (K8s 1.32). Script: `scripts/gatekeeper-test.ps1`. Log: `results/logs/gatekeeper-test-20260325-152857.log`

## 1. Dataset Overview

The evaluation dataset comprises **29 Kubernetes manifests** organised into five categories. Each manifest was evaluated against **5 policies** (9 Rego deny rules) at the CI stage. A subset was additionally evaluated at the admission stage via Gatekeeper.

| Category | Manifests | Purpose |
|---|---|---|
| Compliant | 9 | Confirm that well-formed workloads pass all policies, including edge-case structures |
| Negative control | 5 | Confirm that non-workload resources do not trigger false positives |
| Single violation | 9 | Isolate each policy with exactly one violation |
| Multi-violation (extended) | 6 | Test concurrent violations across policies, containers, and resource types |
| CI bypass (admission) | 5 | Validate Gatekeeper rejects non-compliant manifests applied directly to the cluster |

---

## 2. Compliant Scenarios

All policies satisfied. Expected CI result: **PASS (0 failures)**. Expected admission result (where tested): **ALLOWED**.

| ID | File | Resource | Containers | Key Characteristic | CI | Admission |
|---|---|---|---|---|---|---|
| S01 | `tests/good/deployment-good.yaml` | Deployment | 1 | Reference compliant manifest; all 5 policies satisfied | **PASS** | **ALLOWED** |
| S02 | `tests/good/deployment-minimal.yaml` | Deployment | 1 | Minimal viable compliant spec (alpine:3.19, 10 m CPU) | **PASS** | — |
| S03 | `tests/good/deployment-multi-container.yaml` | Deployment | 2 | Two containers (api + sidecar), both individually compliant | **PASS** | — |
| S04 | `tests/good/statefulset-good.yaml` | StatefulSet | 1 | Stateful workload (postgres:16.2); same `spec.template` path | **PASS** | — |
| S05 | `tests/good/job-good.yaml` | Job | 1 | Batch workload (flyway:10.8); same `spec.template` path | **PASS** | — |
| S30 | `tests/good/deployment-no-privileged-field.yaml` | Deployment | 1 | `privileged` field omitted (not set to `false`); proves P5 treats absence correctly | **PASS** | — |
| S31 | `tests/good/deployment-sha-digest.yaml` | Deployment | 1 | Image by digest (`nginx@sha256:...`); proves P4 handles digests without false-positive | **PASS** | — |
| S32 | `tests/good/deployment-extra-security-fields.yaml` | Deployment | 1 | Hardened `securityContext` with extra keys; proves `object.get` unaffected | **PASS** | — |
| S34 | `tests/good/deployment-init-container.yaml` | Deployment | 1+1 init | Init container (no tag, no `securityContext`) + compliant app; proves policies scope to `containers[_]` only | **PASS** | — |

---

## 3. Negative-Control Scenarios

These resources do not contain the `spec.template.spec.containers` path that all five policies iterate over. They verify that the policy set produces **zero false positives** on non-workload or out-of-scope resources. Expected CI result: **PASS (0 failures)**.

| ID | File | Resource | Why Policies Are Inapplicable | CI |
|---|---|---|---|---|
| S06 | `tests/good/configmap.yaml` | ConfigMap | No container specification | **PASS** |
| S07 | `tests/good/service.yaml` | Service | No container specification | **PASS** |
| S08 | `tests/good/namespace.yaml` | Namespace | Cluster-level resource; no pod template | **PASS** |
| S09 | `tests/good/pod-negative-control.yaml` | Pod (bare) | Uses `spec.containers`, not `spec.template.spec.containers` | **PASS** |
| S33 | `tests/good/cronjob-good.yaml` | CronJob | Uses `spec.jobTemplate.spec.template.spec.containers` (one level deeper) | **PASS** |

> **Note on S09:** This bare Pod intentionally uses `busybox:latest` with no `securityContext`. It passes because the policies' OPA path (`input.spec.template.spec.containers[_]`) does not match bare-Pod structure. This documents a **known scope limitation**: bare Pods are not covered by the current policy set.

> **Note on S33:** This CronJob intentionally uses `busybox:latest` with no `securityContext`. It passes because CronJobs nest containers at `spec.jobTemplate.spec.template.spec.containers` — one level deeper than the path the policies evaluate. This documents a second **scope boundary**.

---

## 4. Single-Violation Scenarios

Each manifest isolates exactly one policy (or one violation mechanism). All other policies are satisfied. Expected CI result: **FAIL** with the stated number of violations.

| ID | File | Resource | Violated Policy | Violation Detail | Failures | CI | Admission |
|---|---|---|---|---|---|---|---|
| S10 | `tests/bad/deployment-root.yaml` | Deployment | P1 | `runAsNonRoot: false` | 1 | **FAIL** | **REJECTED** |
| S11 | `tests/bad/deployment-priv-escalation.yaml` | Deployment | P2 | `allowPrivilegeEscalation: true` | 1 | **FAIL** | **REJECTED** |
| S12 | `tests/bad/deployment-no-resources.yaml` | Deployment | P3 | No `resources` block (4 missing fields) | 4 | **FAIL** | — |
| S13 | `tests/bad/deployment-latest-tag.yaml` | Deployment | P4 | `image: nginx:latest` | 1 | **FAIL** | **REJECTED** |
| S14 | `tests/bad/deployment-privileged.yaml` | Deployment | P5 | `privileged: true` | 1 | **FAIL** | — |
| S15 | `tests/bad/deployment-no-tag.yaml` | Deployment | P4 | `image: nginx` (no colon, no tag) | 1 | **FAIL** | — |
| S35 | `tests/bad/deployment-partial-resources.yaml` | Deployment | P3 | Has `requests` but no `limits`; 2 of 4 P3 rules fire | 2 | **FAIL** | — |
| S36 | `tests/bad/deployment-second-container-violation.yaml` | Deployment | P4 | 1st container compliant; 2nd uses `fluentd:latest` | 1 | **FAIL** | — |
| S37 | `tests/bad/statefulset-latest-tag.yaml` | StatefulSet | P4 | `:latest` tag on non-Deployment resource | 1 | **FAIL** | — |

> S12 produces 4 failures because P3 contains four independent deny rules (one per resource field). S35 produces 2 failures (only the `limits` rules fire). S12, S14, S35, S36, and S37 have no admission result because P3 and P5 are not implemented as Gatekeeper constraints in this PoC, and S36/S37 test structural variation rather than admission enforcement.

---

## 5. Multi-Violation Scenarios (Extended)

Each manifest triggers violations across two or more policies simultaneously. These scenarios test concurrent detection, per-container iteration, and cross-resource-type enforcement. Expected CI result: **FAIL** with the stated number of violations.

| ID | File | Resource | Violated Policies | Violation Detail | Failures | CI | Admission |
|---|---|---|---|---|---|---|---|
| S16 | `tests/bad/deployment-no-security-context.yaml` | Deployment | P1, P2 | `securityContext` omitted entirely; `object.get` defaults trigger both | 2 | **FAIL** | — |
| S18 | `tests/bad/deployment-root-and-escalation.yaml` | Deployment | P1, P2 | Both security fields explicitly set to insecure values | 2 | **FAIL** | — |
| S19 | `tests/bad/deployment-three-violations.yaml` | Deployment | P1, P2, P4 | Root + escalation + `:latest` tag | 3 | **FAIL** | — |
| S22 | `tests/bad/deployment-multi-container-mixed.yaml` | Deployment | P1, P3, P4 | 1st container compliant; sidecar violates P1 + P3 (×4) + P4 | 6 | **FAIL** | — |
| S23 | `tests/bad/job-multi-violation.yaml` | Job | P1, P3, P4 | Job resource: root + `:latest` + no resources | 6 | **FAIL** | — |
| S24 | `tests/bad/deployment-multi-violation.yaml` | Deployment | P1-P5 | All policies violated simultaneously (maximum-violation reference) | 8 | **FAIL** | **REJECTED** |

### S24 — Detailed Violation Breakdown

S24 triggers every deny rule except one (P4's "no tag" rule does not fire because the image has a `:latest` tag, so the `:latest` rule fires instead).

| # | Policy | Conftest Message |
|---|---|---|
| 1 | P1 | Container 'app' must set securityContext.runAsNonRoot to true |
| 2 | P2 | Container 'app' must set securityContext.allowPrivilegeEscalation to false |
| 3 | P3 | Container 'app' must define resources.requests.cpu |
| 4 | P3 | Container 'app' must define resources.requests.memory |
| 5 | P3 | Container 'app' must define resources.limits.cpu |
| 6 | P3 | Container 'app' must define resources.limits.memory |
| 7 | P4 | Container 'app' uses image 'nginx:latest' with ':latest' tag - use a pinned version instead |
| 8 | P5 | Container 'app' must not run in privileged mode |

At the admission stage, Gatekeeper reported 3 of the 8 violations (P1, P2, P4) because only those policies have corresponding ConstraintTemplates.

---

## 6. CI Bypass Mitigation — Gatekeeper Admission Control ★

> **This is the central evaluation scenario.** It validates the defence-in-depth
> property of the architecture: even when a developer or automated process
> applies a manifest directly to the cluster — completely bypassing the CI
> pipeline — Gatekeeper's validating admission webhook blocks non-compliant
> resources at the Kubernetes API server. This scenario group provides the
> primary evidence for **RQ3** (_Does admission control mitigate CI bypass
> risks?_) and is a necessary complement to the CI-stage results that support
> **RQ1** and **RQ2**.

### 6.1 Threat Model

CI-stage policy enforcement depends on every deployment flowing through the
pipeline. In practice, this assumption can be violated in several ways:

| Bypass Vector | Example |
|---|---|
| Direct `kubectl apply` | A developer or operator applies a manifest from a local machine |
| Emergency hotfix | A time-critical change is pushed to the cluster without waiting for CI |
| Service account misuse | An automated process with cluster credentials deploys without triggering a pipeline |
| Misconfigured pipeline | A new repository or branch lacks the Conftest validation step |

In all cases, the manifest reaches the Kubernetes API server without having
been evaluated by Conftest. The question is whether Gatekeeper's admission
webhook — which operates inside the API server's admission chain — can detect
and reject the same violations that CI would have caught.

### 6.2 Method

Each manifest was applied with `kubectl apply --dry-run=server`, which sends
the request through the full admission chain (including Gatekeeper webhooks)
without persisting the resource to etcd. This simulates a bypass scenario
while keeping the test non-destructive and reproducible.

**Gatekeeper constraints enforced:** P1 (no-root), P2 (no-priv-escalation),
P4 (no-latest-tag).
P3 and P5 are enforced at CI only and are **not** implemented as Gatekeeper
constraints in this PoC.

### 6.3 Baseline: Compliant Manifest (S25)

| Field | Value |
|---|---|
| **Scenario** | S25 — Compliant bypass baseline |
| **Manifest** | `tests/good/deployment-good.yaml` |
| **What is bypassed** | CI pipeline (Conftest not executed) |
| **Policies evaluated at admission** | P1, P2, P4 |
| **Expected admission result** | ALLOWED |
| **Actual admission result** | **ALLOWED** |
| **Why it matters** | Confirms that a compliant manifest is not incorrectly rejected when applied outside the CI path. Without this baseline, a rejection in S26–S29 could be attributed to a misconfigured webhook rather than to policy logic. |

### 6.4 Single-Policy Bypass Scenarios (S26–S28)

Each scenario applies a manifest that violates exactly one admission-enforced
policy. The manifest was already validated at the CI stage (Sections 4–5),
so the expected violation is known. The test confirms that Gatekeeper
independently reaches the same conclusion.

| ID | Scenario | Manifest | Policy Bypassed | Expected | Actual | Violation Message |
|---|---|---|---|---|---|---|
| S26 | Root container bypass | `deployment-root.yaml` | P1 | REJECTED | **REJECTED** | Container 'app' must set securityContext.runAsNonRoot to true |
| S27 | Privilege escalation bypass | `deployment-priv-escalation.yaml` | P2 | REJECTED | **REJECTED** | Container 'app' must set securityContext.allowPrivilegeEscalation to false |
| S28 | Latest-tag bypass | `deployment-latest-tag.yaml` | P4 | REJECTED | **REJECTED** | Container 'app' uses image 'nginx:latest' with ':latest' tag - use a pinned version |

**Why these matter:** Each scenario demonstrates that a single insecure
configuration — which would have been caught by Conftest in the CI pipeline —
is independently detected and blocked by Gatekeeper at the API server level.
The one-to-one correspondence between CI violations (S10, S11, S13) and
admission rejections (S26, S27, S28) provides direct evidence that the two
enforcement points evaluate the same policy semantics.

### 6.5 Multi-Policy Bypass Scenario (S29)

| Field | Value |
|---|---|
| **Scenario** | S29 — Maximum-violation bypass |
| **Manifest** | `tests/bad/deployment-multi-violation.yaml` |
| **What is bypassed** | CI pipeline (Conftest not executed) |
| **CI result for same manifest** | FAIL with 8 violations across P1–P5 (see S24) |
| **Policies evaluated at admission** | P1, P2, P4 (3 of 5) |
| **Expected admission result** | REJECTED |
| **Actual admission result** | **REJECTED** |
| **Violations reported by Gatekeeper** | 3 (P1: runAsNonRoot, P2: allowPrivilegeEscalation, P4: latest tag) |
| **Violations not reported (CI-only)** | 5 (P3 ×4: resource fields, P5: privileged mode) |

**Why this matters:** This is the most demanding bypass scenario. The manifest
violates all five policies simultaneously, but only three are enforced at the
admission stage. The test confirms two properties:

1. **Concurrent detection at admission.** Gatekeeper evaluates all three
   constraints and reports all three violations in a single rejection — it
   does not stop at the first failing constraint.

2. **Partial coverage is explicit.** The 5 violations detected by Conftest
   but not by Gatekeeper (P3 ×4 and P5) are a documented scope limitation,
   not a detection failure. They demonstrate the complementarity argument
   central to RQ2: CI and admission each contribute coverage that the other
   lacks.

### 6.6 Summary of Bypass Results

| ID | Manifest | Policies Enforced | Expected | Actual | Outcome |
|---|---|---|---|---|---|
| S25 | `deployment-good.yaml` | — | ALLOWED | **ALLOWED** | ✔ |
| S26 | `deployment-root.yaml` | P1 | REJECTED | **REJECTED** | ✔ |
| S27 | `deployment-priv-escalation.yaml` | P2 | REJECTED | **REJECTED** | ✔ |
| S28 | `deployment-latest-tag.yaml` | P4 | REJECTED | **REJECTED** | ✔ |
| S29 | `deployment-multi-violation.yaml` | P1, P2, P4 | REJECTED | **REJECTED** | ✔ |

**Result:** 5 bypass tests, 5 expected outcomes, **0 unexpected outcomes**.

### 6.7 What Is and Is Not Mitigated

| Bypass Risk | Mitigated? | Evidence |
|---|---|---|
| Direct `kubectl apply` violating P1 (root) | **Yes** | S26 rejected |
| Direct `kubectl apply` violating P2 (priv escalation) | **Yes** | S27 rejected |
| Direct `kubectl apply` violating P4 (latest tag) | **Yes** | S28 rejected |
| Direct `kubectl apply` violating P1 + P2 + P4 concurrently | **Yes** | S29 rejected with 3 violations |
| Direct `kubectl apply` violating P3 (resource limits) | **No** | No ConstraintTemplate for P3 (CI-only) |
| Direct `kubectl apply` violating P5 (privileged mode) | **No** | No ConstraintTemplate for P5 (CI-only) |
| Bare Pod or CronJob bypass | **No** | Policies use `spec.template.spec.containers` path (S09, S33) |
| Gatekeeper webhook disabled by cluster admin | **No** | Outside PoC scope; requires RBAC controls |
| Resources applied before Gatekeeper installation | **No** | Gatekeeper's audit controller can detect post-deployment, but does not block |

### 6.8 Significance for the Dissertation

The CI bypass scenarios (S25–S29) occupy a central position in the evaluation
because they test the property that distinguishes a multi-stage enforcement
architecture from a CI-only approach. A CI pipeline that validates Kubernetes
manifests against Rego policies — as demonstrated in Sections 2–5 — provides
governance coverage only when deployments flow through that pipeline. In any
environment where direct cluster access is possible, CI-stage enforcement
alone is insufficient: a single `kubectl apply` from a developer workstation
or an automated process with cluster credentials can introduce configurations
that violate the organisation's security policies without triggering any
validation.

Admission control addresses this gap by embedding policy evaluation inside the
Kubernetes API server's request processing chain, where it operates
independently of the deployment mechanism. The bypass scenarios demonstrate
this property empirically: the same manifests that were rejected by Conftest
at the CI stage (S10, S11, S13, S24) are also rejected by Gatekeeper at the
admission stage (S26, S27, S28, S29) — even though the CI pipeline was not
involved. This result provides direct evidence for RQ3 and reinforces the
complementarity argument of RQ2.

The evaluation is deliberately conservative in its claims. Two of the five
policies (P3, P5) are not enforced at the admission stage, and the reasons
for this scope decision are documented. The admission-stage coverage is
therefore partial: it mitigates bypass risks for the three policies with
ConstraintTemplates but does not eliminate all bypass vectors. This
limitation is inherent to the proof-of-concept design, not to the
architectural pattern, and is acknowledged as a boundary condition of the
evaluation.

---

## 7. Aggregate Results

### CI Enforcement (Conftest) - All 29 Manifests

| Category | Manifests | Assertions | Passed | Failures |
|---|---|---|---|---|
| Compliant (S01-S05, S30-S32, S34) | 9 | 81 | 81 | 0 |
| Negative control (S06-S09, S33) | 5 | 45 | 45 | 0 |
| Single violation (S10-S15, S35-S37) | 9 | 81 | 68 | 13 |
| Multi-violation (S16, S18-S19, S22-S24) | 6 | 54 | 27 | 27 |
| **Total** | **29** | **261** | **221** | **40** |

> Each manifest is evaluated against 9 deny rules (one assertion per rule), regardless of the number of containers. A rule that iterates over multiple containers can produce multiple failure messages within a single assertion.

### Admission Enforcement (Gatekeeper) — 5 Manifests

| Metric | Value |
|---|---|
| Policies enforced | 3 (P1, P2, P4) |
| ConstraintTemplates | 3 |
| Constraints | 3 |
| Manifests tested | 5 (S25-S29) |
| Expected outcomes | 5 |
| Unexpected outcomes | 0 |

### Combined

| Metric | Value |
|---|---|
| Total enforcement points | 2 (CI + Admission) |
| Total policies | 5 (CI: 5, Admission: 3) |
| Total unique manifests | 29 |
| Total test scenarios (incl. admission re-use) | 34 |
| False positives | 0 |
| False negatives | 0 |
| CI bypass blocked by Gatekeeper (S25-S29) | Yes |

---

## 8. Design Rationale for the Dataset

The 29 manifests and 34 scenarios were chosen to address the following evaluation dimensions:

| Dimension | Scenarios | What It Demonstrates |
|---|---|---|
| **Per-policy isolation** | S10-S15, S35-S37 | Each policy can be triggered independently |
| **Concurrent violations** | S16, S18-S19, S22-S24 | Multiple policies fire simultaneously on a single container |
| **Per-container iteration** | S03, S34, S36, S22 | Policies evaluate each container independently within a pod |
| **Partial compliance** | S35 | A subset of P3 rules fires when some fields are present |
| **Omitted fields** | S16, S30 | `object.get` defaults correctly trigger deny rules; omitted `privileged` does not false-positive |
| **Image reference formats** | S31 | Digest-based references (`@sha256:...`) handled correctly by P4 |
| **Hardened securityContext** | S32 | Extra security fields do not interfere with `object.get` evaluation |
| **Init containers** | S34 | Policies scope to `containers[_]` only, not `initContainers` |
| **Resource type breadth** | S04, S05, S37, S23 | Same policies apply to StatefulSet and Job resources |
| **Negative controls** | S06-S09, S33 | Policies do not false-positive on out-of-scope resources |
| **Known scope limitations** | S09, S33 | Bare Pods and CronJobs are not covered by the policy path |
| **Defence in depth** | S25-S29 | Admission control blocks violations even when CI is bypassed |