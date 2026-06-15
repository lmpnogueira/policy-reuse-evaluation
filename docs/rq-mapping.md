# Research Question Mapping

> This document maps the evaluation scenarios and evidence collected in the
> proof of concept to the three research questions that guide the dissertation.
> It is intended to make the link between empirical results and analytical
> conclusions explicit and traceable.

---

## Research Questions

| ID | Research Question |
|---|---|
| **RQ1** | Can Policy-as-Code enforcement detect insecure Kubernetes configurations automatically? |
| **RQ2** | Does multi-stage enforcement (CI + admission control) improve governance coverage? |
| **RQ3** | Does admission control mitigate CI bypass risks? |

---

## RQ1 — Automatic Detection of Insecure Configurations

### What Must Be Demonstrated

That a set of Rego policies, evaluated by Conftest against Kubernetes manifests,
can (a) correctly identify known insecure configurations and (b) avoid
false positives on compliant or structurally unrelated inputs — without manual
inspection.

### Contributing Scenarios

| Scenario Group | IDs | Contribution to RQ1 |
|---|---|---|
| Single-violation | S10–S15, S35–S37 | Each policy is triggered in isolation; confirms that the engine attributes the violation to the correct rule |
| Multi-violation | S16, S18–S19, S22–S24 | Multiple policies fire concurrently; confirms the engine reports all applicable violations in one pass |
| Compliant baselines | S01–S05, S30–S32, S34 | Zero false positives across 9 structurally diverse compliant manifests |
| Negative controls | S06–S09, S33 | Zero false positives on 5 non-workload resources (ConfigMap, Service, Namespace, bare Pod, CronJob) |

### Key Results

| Metric | Value | Source |
|---|---|---|
| Policies evaluated | 5 (P1–P5), encoded as 9 deny rules | `policies/kubernetes/*.rego` |
| Total manifests | 29 | `tests/good/` (14) + `tests/bad/` (15) |
| Total assertions | 261 | `conftest-test-20260415-111740.log` |
| Violations correctly detected | 40 | All in `tests/bad/` |
| False positives | 0 | No compliant or non-target manifest flagged |
| False negatives | 0 | Every known violation produced the expected deny message |
| Per-policy trigger count | P1: 7, P2: 5, P3: 5, P4: 8, P5: 2 | `docs/dataset.md` §5.4 |

### Conclusion (Conservative)

Within the scope of the five policies and 29 manifests evaluated, the
Policy-as-Code approach detected all intentionally introduced insecure
configurations automatically, with zero false positives and zero false
negatives. Each policy was triggered by at least two independent test cases,
providing evidence that the detection is attributable to the policy logic
rather than to a single manifest structure.

These results do not generalise beyond the tested policy set and resource
types. In particular, the policies evaluate only the
`spec.template.spec.containers` path, so resource types with different
container nesting (bare Pods, CronJobs) and `initContainers` fall outside
the current detection scope (documented as known limitations in S09, S33,
and S34).

---

## RQ2 — Governance Coverage Through Multi-Stage Enforcement

### What Must Be Demonstrated

That combining CI-stage validation (Conftest) with admission-stage enforcement
(Gatekeeper) provides broader governance coverage than either stage alone, and
that the two stages are complementary rather than redundant.

### Contributing Scenarios

| Scenario Group | IDs | Contribution to RQ2 |
|---|---|---|
| CI-only policies | S12, S14, S35 | P3 and P5 violations are detected at CI but have no Gatekeeper constraint; demonstrates CI-exclusive coverage |
| Admission-enforced policies | S25–S29 | P1, P2, and P4 violations are rejected at admission; demonstrates admission-exclusive coverage when CI is bypassed |
| Dual-enforced violations | S10, S11, S13, S24 | These manifests are rejected at both CI and admission; confirms that the two stages agree on the same input |
| Compliant at both stages | S01 (CI) + S25 (admission) | The same manifest passes at both enforcement points; confirms no inter-stage conflict |

### Key Results

| Metric | CI (Conftest) | Admission (Gatekeeper) |
|---|---|---|
| Policies enforced | 5 (P1–P5) | 3 (P1, P2, P4) |
| Manifests evaluated | 29 | 5 |
| Violations detected | 40 | 4 rejections |
| Compliant inputs accepted | 14 | 1 |
| False positives | 0 | 0 |
| Unexpected outcomes | 0 | 0 |

### Coverage Complementarity

| Policy | CI | Admission | Gap if CI Only | Gap if Admission Only |
|---|---|---|---|---|
| P1 (no root) | ✔ | ✔ | Bypass risk | None for P1 |
| P2 (no priv escalation) | ✔ | ✔ | Bypass risk | None for P2 |
| P3 (resource limits) | ✔ | ✘ | Bypass risk | P3 undetected entirely |
| P4 (no latest tag) | ✔ | ✔ | Bypass risk | None for P4 |
| P5 (no privileged) | ✔ | ✘ | Bypass risk | P5 undetected entirely |

### Conclusion (Conservative)

The two enforcement stages are complementary within this PoC. CI-stage
validation covers all five policies and produces detailed per-rule violation
messages suitable for developer feedback. Admission-stage enforcement covers
three of the five policies and acts as a safety net when the CI pipeline is
not in the deployment path.

Neither stage alone achieves the coverage of both combined: CI alone is
susceptible to bypass (see RQ3), while admission alone misses P3 and P5
because no corresponding ConstraintTemplates were implemented. The PoC
demonstrates the architectural pattern, but the governance improvement is
limited to the three policies that are enforced at both stages.

No claim is made that multi-stage enforcement eliminates all governance gaps.
The two uncovered policies (P3, P5) at the admission stage represent a
deliberate scope decision, not a technical limitation — the same
ConstraintTemplate pattern used for P1, P2, and P4 could be extended to
P3 and P5.

---

## RQ3 — CI Bypass Mitigation Through Admission Control

### What Must Be Demonstrated

That when a Kubernetes manifest is applied directly to the cluster — bypassing
the CI pipeline entirely — OPA Gatekeeper's validating admission webhook
rejects manifests that violate enforced policies.

### Contributing Scenarios

| ID | Manifest | Bypass Action | Policies Enforced | Outcome |
|---|---|---|---|---|
| S25 | `deployment-good.yaml` | `kubectl apply --dry-run=server` | — | **ALLOWED** |
| S26 | `deployment-root.yaml` | `kubectl apply --dry-run=server` | P1 | **REJECTED** |
| S27 | `deployment-priv-escalation.yaml` | `kubectl apply --dry-run=server` | P2 | **REJECTED** |
| S28 | `deployment-latest-tag.yaml` | `kubectl apply --dry-run=server` | P4 | **REJECTED** |
| S29 | `deployment-multi-violation.yaml` | `kubectl apply --dry-run=server` | P1, P2, P4 | **REJECTED** |

### Key Results

| Metric | Value |
|---|---|
| Manifests applied directly (bypassing CI) | 5 |
| Expected rejections | 4 |
| Actual rejections | 4 |
| Expected acceptances | 1 |
| Actual acceptances | 1 |
| Unexpected outcomes | 0 |

### What Is Not Mitigated

| Gap | Reason | Impact |
|---|---|---|
| P3 (resource limits) bypass | No Gatekeeper ConstraintTemplate for P3 | A manifest with missing resource requests/limits can be applied directly to the cluster |
| P5 (privileged mode) bypass | No Gatekeeper ConstraintTemplate for P5 | A manifest with `privileged: true` can be applied directly to the cluster |
| Bare Pods and CronJobs | Policies use `spec.template.spec.containers` path | These resource types bypass both CI and admission policy evaluation |

### Conclusion (Conservative)

For the three policies implemented as Gatekeeper constraints (P1, P2, P4),
admission control successfully rejected all non-compliant manifests applied
directly to the cluster, with zero false positives. This demonstrates that
the defence-in-depth pattern — where admission control acts as a second
enforcement point independent of the CI pipeline — is viable for mitigating
CI bypass risks.

The mitigation is partial: two policies (P3, P5) are enforced at CI only,
so a direct `kubectl apply` that violates P3 or P5 would succeed. This is a
scope limitation of the PoC, not a fundamental constraint of the architecture.

No claim is made that admission control eliminates all bypass vectors. In
particular, cluster administrators with sufficient RBAC privileges can
disable or modify Gatekeeper constraints, and resources applied before
Gatekeeper installation are not retroactively evaluated (though Gatekeeper's
audit controller can detect them post-deployment).

---

## Evaluation Summary Tables

The three tables below consolidate the evaluation results into a format
suitable for the dissertation's evaluation chapter. Each table is followed
by a short interpretive paragraph.

### Table 1 — RQ1: Detection Accuracy

| Category | Manifests | Expected Failures | Correct Detections | False Negatives | False Positives |
|---|---|---|---|---|---|
| Compliant baselines | 9 | 0 | — | — | 0 |
| Negative controls | 5 | 0 | — | — | 0 |
| Single-policy violations | 9 | 13 | 13 | 0 | 0 |
| Multi-policy violations | 6 | 27 | 27 | 0 | 0 |
| **Total** | **29** | **40** | **40** | **0** | **0** |

Across 29 manifests and 261 assertions, the five Rego policies correctly
identified all 40 expected violations without producing any false negatives
or false positives. The 14 compliant and non-target manifests — which include
edge-case structures such as digest-based image references, omitted
`privileged` fields, hardened security contexts, and init containers — were
all accepted without spurious failures. These results indicate that, within
the evaluated policy scope, Policy-as-Code enforcement achieves accurate
automatic detection of the tested insecure configuration patterns.

### Table 2 — RQ2: Multi-Stage Governance Coverage

| Enforcement Stage | Compliant (S01/S25) | Single Violation (P1) | Single Violation (P4) | Multi-Violation (P1-P5) | Governance Contribution |
|---|---|---|---|---|---|
| CI (Conftest) | PASS | FAIL — 1 violation | FAIL — 1 violation | FAIL — 8 violations | Covers all 5 policies; provides detailed per-rule feedback |
| Admission (Gatekeeper) | ALLOWED | REJECTED — P1 | REJECTED — P4 | REJECTED — 3 of 8 (P1, P2, P4) | Covers 3 policies; blocks bypass for P1, P2, P4 |
| Neither stage | — | — | — | P3, P5 undetected | Gap: P3 and P5 require CI; no admission fallback |

The two enforcement stages are complementary. CI-stage validation covers all
five policies and produces granular violation messages suitable for developer
feedback loops. Admission-stage enforcement covers three of the five policies
and provides a safety net that operates independently of the deployment
mechanism. Neither stage alone achieves the coverage of both combined: CI
alone is vulnerable to bypass, while admission alone misses P3 (resource
limits) and P5 (privileged mode). The table makes explicit that the
governance improvement from multi-stage enforcement is bounded by the number
of policies implemented at each stage.

### Table 3 — RQ3: CI Bypass Mitigation

| Scenario | Bypass Method | Manifest | Admission Result | Security Implication |
|---|---|---|---|---|
| S25 — Compliant baseline | `kubectl apply --dry-run=server` | `deployment-good.yaml` | **ALLOWED** | Confirms no false rejection on bypass path |
| S26 — Root container | `kubectl apply --dry-run=server` | `deployment-root.yaml` | **REJECTED** | P1 violation blocked without CI involvement |
| S27 — Privilege escalation | `kubectl apply --dry-run=server` | `deployment-priv-escalation.yaml` | **REJECTED** | P2 violation blocked without CI involvement |
| S28 — Latest tag | `kubectl apply --dry-run=server` | `deployment-latest-tag.yaml` | **REJECTED** | P4 violation blocked without CI involvement |
| S29 — All policies violated | `kubectl apply --dry-run=server` | `deployment-multi-violation.yaml` | **REJECTED** (3 violations) | P1 + P2 + P4 blocked concurrently; P3 + P5 not enforced |

All four non-compliant manifests applied directly to the cluster — bypassing
the CI pipeline entirely — were rejected by Gatekeeper's admission webhook.
The compliant manifest was correctly accepted, confirming that the webhook
does not introduce false rejections on the bypass path. The multi-violation
scenario (S29) demonstrates that Gatekeeper evaluates all applicable
constraints concurrently rather than halting at the first failure. The two
policies without ConstraintTemplates (P3, P5) represent a documented scope
boundary: admission control mitigates bypass risks for the three implemented
policies but does not eliminate all bypass vectors.

---

## Summary Table

| RQ | Evaluation Goal | Relevant Scenarios | Evidence Type | Expected Conclusion |
|---|---|---|---|---|
| **RQ1** | Confirm that Rego policies detect all known insecure configurations without false positives | S01–S16, S18–S19, S22–S24, S30–S37 | 261 Conftest assertions across 29 manifests; 40 violations detected, 0 FP, 0 FN | Policy-as-Code detects the tested insecure patterns automatically within the defined policy scope |
| **RQ2** | Show that CI + admission provides broader coverage than either alone | S10–S14, S24 (dual), S12/S14/S35 (CI-only), S25–S29 (admission-only) | Side-by-side comparison of policy coverage at each stage; complementarity matrix | Multi-stage enforcement is complementary: CI covers all 5 policies, admission covers 3, and neither alone matches the combined coverage |
| **RQ3** | Demonstrate that Gatekeeper blocks violations when CI is bypassed | S25–S29 | 5 direct `kubectl apply --dry-run=server` tests; 4 rejections, 1 acceptance, 0 unexpected | Admission control mitigates CI bypass for the 3 policies with ConstraintTemplates; 2 policies remain CI-only |

---

## Per-Manifest Result Summary

The table below provides a single-row-per-manifest view of the entire
evaluation. It is derived from the Conftest log
(`conftest-test-20260415-111740.log`) and the Gatekeeper log
(`gatekeeper-test-20260325-152857.log`). The CSV source is
`results/summary/manifest-results.csv`.

| ID | File | Type | Category | Exp. CI | Act. CI | Exp. Adm. | Act. Adm. | Policies | Status |
|---|---|---|---|---|---|---|---|---|---|
| D-01 | `deployment-good.yaml` | Deployment | Compliant | PASS | PASS | ALLOWED | ALLOWED | — | ✔ |
| D-02 | `deployment-minimal.yaml` | Deployment | Compliant | PASS | PASS | — | — | — | ✔ |
| D-03 | `deployment-multi-container.yaml` | Deployment | Compliant | PASS | PASS | — | — | — | ✔ |
| D-04 | `statefulset-good.yaml` | StatefulSet | Compliant | PASS | PASS | — | — | — | ✔ |
| D-05 | `job-good.yaml` | Job | Compliant | PASS | PASS | — | — | — | ✔ |
| D-30 | `deployment-no-privileged-field.yaml` | Deployment | Compliant | PASS | PASS | — | — | — | ✔ |
| D-31 | `deployment-sha-digest.yaml` | Deployment | Compliant | PASS | PASS | — | — | — | ✔ |
| D-32 | `deployment-extra-security-fields.yaml` | Deployment | Compliant | PASS | PASS | — | — | — | ✔ |
| D-34 | `deployment-init-container.yaml` | Deployment | Compliant | PASS | PASS | — | — | — | ✔ |
| D-06 | `deployment-root.yaml` | Deployment | Single | FAIL | FAIL | REJECTED | REJECTED | P1 | ✔ |
| D-07 | `deployment-priv-escalation.yaml` | Deployment | Single | FAIL | FAIL | REJECTED | REJECTED | P2 | ✔ |
| D-08 | `deployment-no-resources.yaml` | Deployment | Single | FAIL | FAIL | — | — | P3 | ✔ |
| D-09 | `deployment-latest-tag.yaml` | Deployment | Single | FAIL | FAIL | REJECTED | REJECTED | P4 | ✔ |
| D-10 | `deployment-privileged.yaml` | Deployment | Single | FAIL | FAIL | — | — | P5 | ✔ |
| D-11 | `deployment-no-tag.yaml` | Deployment | Single | FAIL | FAIL | — | — | P4 | ✔ |
| D-12 | `deployment-partial-resources.yaml` | Deployment | Single | FAIL | FAIL | — | — | P3 | ✔ |
| D-16 | `deployment-second-container-violation.yaml` | Deployment | Single | FAIL | FAIL | — | — | P4 | ✔ |
| D-17 | `statefulset-latest-tag.yaml` | StatefulSet | Single | FAIL | FAIL | — | — | P4 | ✔ |
| D-13 | `deployment-no-security-context.yaml` | Deployment | Multi | FAIL | FAIL | — | — | P1, P2 | ✔ |
| D-14 | `deployment-root-and-escalation.yaml` | Deployment | Multi | FAIL | FAIL | — | — | P1, P2 | ✔ |
| D-15 | `deployment-three-violations.yaml` | Deployment | Multi | FAIL | FAIL | — | — | P1, P2, P4 | ✔ |
| D-18 | `deployment-multi-container-mixed.yaml` | Deployment | Multi | FAIL | FAIL | — | — | P1, P3, P4 | ✔ |
| D-19 | `job-multi-violation.yaml` | Job | Multi | FAIL | FAIL | — | — | P1, P3, P4 | ✔ |
| D-20 | `deployment-multi-violation.yaml` | Deployment | Multi | FAIL | FAIL | REJECTED | REJECTED | P1–P5 | ✔ |
| D-21 | `configmap.yaml` | ConfigMap | Non-target | PASS | PASS | — | — | — | ✔ |
| D-22 | `service.yaml` | Service | Non-target | PASS | PASS | — | — | — | ✔ |
| D-23 | `namespace.yaml` | Namespace | Non-target | PASS | PASS | — | — | — | ✔ |
| D-24 | `pod-negative-control.yaml` | Pod | Non-target | PASS | PASS | — | — | — | ✔ |
| D-33 | `cronjob-good.yaml` | CronJob | Non-target | PASS | PASS | — | — | — | ✔ |

**29 manifests. 29 correct outcomes. 0 unexpected results.**

### How This Table Supports Each Research Question

**RQ1 — Automatic detection.** Filter the table by `Status = ✔` and
`Category ∈ {Single, Multi}`. Every non-compliant manifest was correctly
detected (FAIL at CI), confirming zero false negatives. Filter by
`Category ∈ {Compliant, Non-target}` to confirm zero false positives.
The `Policies` column traces each detection to the specific rule(s) that
fired, supporting the claim that violations are attributable to policy logic
rather than to testing artefacts.

**RQ2 — Multi-stage coverage.** Compare the `Act. CI` and `Act. Adm.`
columns for manifests that have both values (D-01, D-06, D-07, D-09, D-20).
All five show consistent outcomes across stages. Manifests where
`Act. Adm. = —` (e.g. D-08, D-10) identify the governance gap: these
policies are enforced at CI only. The table makes the complementarity
argument visible in a single view.

**RQ3 — CI bypass mitigation.** The `Act. Adm.` column for D-06, D-07,
D-09, and D-20 shows REJECTED — these are the same manifests used in the
bypass scenarios (S26–S29). The table confirms that admission control
independently reaches the same rejection decision as CI, without the CI
pipeline being involved.

---

## Traceability

| Document | Role in RQ Mapping |
|---|---|
| `docs/scenarios.md` | Defines all scenario IDs (S01–S37) with expected and actual outcomes |
| `docs/dataset.md` | Catalogues all 29 manifests (D-01–D-34) with origin, classification, and policy coverage |
| `docs/evaluation-plan.md` | Describes test procedures, tooling, and success criteria |
| `docs/policies.md` | Documents P1–P5 with Rego rule details and enforcement points |
| `results/summary/manifest-results.csv` | One-row-per-manifest result summary with CI and admission outcomes |
| `results/logs/conftest-test-20260415-111740.log` | CI evaluation evidence (261 assertions) |
| `results/logs/gatekeeper-test-20260325-152857.log` | Admission evaluation evidence (5 tests) |

---

## Scope Disclaimer

The conclusions drawn above apply strictly to the proof-of-concept scope:

- **5 policies** (P1–P5) covering container security context, resource limits, image tags, and privileged mode.
- **29 manifests** authored for the evaluation (18 synthetic, 8 adapted realistic, 3 realistic). None were extracted from production systems.
- **3 resource types** with policy-relevant structure (Deployment, StatefulSet, Job). Five additional types serve as negative controls.
- **2 enforcement points** (Conftest at CI, Gatekeeper at admission). No runtime enforcement was evaluated.

Generalisation beyond this scope — to other policy domains, larger policy sets,
production workloads, or alternative policy engines — requires additional
evaluation and is explicitly outside the claims of this dissertation.
