# Evaluation Plan

## Objective

Validate that the Policy-as-Code implementation correctly enforces all five security policies (P1–P5) against Kubernetes Deployment manifests, and that compliant manifests are accepted while non-compliant manifests are rejected.

---

## Tooling

| Component | Version | Purpose |
|---|---|---|
| Conftest | 0.67.1 | CLI policy evaluation against YAML manifests |
| OPA | 1.14.1 (bundled) | Rego policy engine used by Conftest |
| Rego | v1 syntax | Policy language with `import rego.v1` |
| OPA Gatekeeper | 3.18.0 | Kubernetes admission controller |
| kind | 0.27.0 | Local Kubernetes cluster (K8s 1.32) |
| kubectl | 1.32.3 | Kubernetes CLI |
| PowerShell | 5.1 (Windows) | Test automation script |

---

## Test Environment

- **OS:** Windows 10/11
- **Shell:** PowerShell 5.1
- **Script:** `scripts/conftest-test.ps1`
- **Policies:** `policies/kubernetes/*.rego` (5 files, 9 deny rules total)
- **Test manifests:** `tests/good/` (14 files) and `tests/bad/` (15 files) — 29 manifests total
- **Log output:** `results/logs/conftest-test-<timestamp>.log`

---

## Test Procedure

### Step 1 — Prerequisites

Ensure `conftest` is installed and available in `PATH`:

```powershell
conftest --version
# Expected: Conftest: 0.67.1
```

### Step 2 — Run the Test Script

From the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\conftest-test.ps1
```

### Step 3 — Verify Output

The script executes three sections:

| Section | Description | Criteria |
|---|---|---|
| **1 — Good manifests** | Run Conftest on `tests/good/*.yaml` | All must produce exit code 0 (no violations) |
| **2 — Bad manifests** | Run Conftest on `tests/bad/*.yaml` | All must produce exit code ≠ 0 (violations found) |
| **3 — Multi-violation** | Count FAIL lines for `deployment-multi-violation.yaml` | Must detect ≥ 5 distinct violations |

### Step 4 — Review Log

All output is saved to `results/logs/conftest-test-<timestamp>.log` for traceability and inclusion in thesis appendices.

---

## Success Criteria

The evaluation is considered **successful** when all of the following hold:

1. **Good manifests pass** — All 14 manifests in `tests/good/` trigger 0 failures across all 9 rules (81 assertions, 0 failures).
2. **Bad manifests fail** — All 15 manifests in `tests/bad/` trigger the expected policy failure(s) (180 assertions, 40 failures).
3. **Multi-violation detection** — `deployment-multi-violation.yaml` triggers 8 distinct violations (all 5 policies).
4. **Zero false positives** — No compliant manifest or non-target resource is incorrectly flagged.
5. **Zero false negatives** — No known violation is missed by the policy set.
6. **Log is generated** — A timestamped log file exists in `results/logs/`.

---

## Metrics Collected

| Metric | Source | Purpose |
|---|---|---|
| Total tests run | Script summary | Completeness |
| Expected results | Script summary | Correctness |
| Unexpected results | Script summary | Error detection |
| Violation count per manifest | Conftest output | Granularity of enforcement |
| Violations per policy | Conftest FAIL lines | Policy-level coverage |
| Test execution timestamp | Log filename | Reproducibility |

---

## Comparison: Baseline vs. Policy-as-Code

| Aspect | Baseline (`baseline-test.sh`) | Policy-as-Code (`conftest-test.ps1`) |
|---|---|---|
| Tool | `kubectl apply --dry-run` | Conftest + OPA/Rego |
| Enforcement | None — Kubernetes accepts all | 5 policies, 9 rules |
| Bad manifests blocked | 0 / 15 | 15 / 15 |
| Violations detected | 0 | 40 total across all bad manifests |
| Audit trail | Basic stdout | Structured log with per-file results |
| Reproducibility | Requires running cluster | Requires only Conftest binary |

---

## Limitations

- CI-stage enforcement (Conftest) covers all 5 policies (P1-P5). Admission control (Gatekeeper) covers 3 policies (P1, P2, P4) due to Gatekeeper's per-request rejection model.
- Tests run on a local Windows workstation. CI pipeline runs on GitHub Actions (Ubuntu).
- The dataset covers 8 resource types (Deployment, StatefulSet, Job, CronJob, ConfigMap, Service, Namespace, Pod) but only 3 (Deployment, StatefulSet, Job) share the `spec.template.spec.containers` path evaluated by the policies. CronJob, bare Pod, and non-workload resources serve as negative controls.
- The policy set is intentionally small (5 policies) to match the proof-of-concept scope.
- Gatekeeper admission tests use `kubectl apply --dry-run=server` to validate rejection without persisting resources.

---

## Gatekeeper Admission Control Evaluation

### Objective

Validate that OPA Gatekeeper enforces policies P1, P2, and P4 at the Kubernetes API server level, rejecting non-compliant Deployments even if CI validation is bypassed.

### Test Environment

- **Cluster:** kind v0.27.0 (Kubernetes 1.32.2), cluster name `pac-poc`
- **Gatekeeper:** v3.18.0 (installed from official manifest)
- **Shell:** PowerShell 5.1 (Windows)
- **Script:** `scripts/gatekeeper-test.ps1`
- **Log output:** `results/logs/gatekeeper-test-<timestamp>.log`

### Gatekeeper Policies

Three policies were selected for admission control enforcement:

| Policy | ConstraintTemplate | Constraint | Rego Package |
|---|---|---|---|
| P1 - No root | `gatekeeper/templates/no-root-template.yaml` | `gatekeeper/constraints/no-root-constraint.yaml` | `k8snoroot` |
| P2 - No priv escalation | `gatekeeper/templates/no-priv-escalation-template.yaml` | `gatekeeper/constraints/no-priv-escalation-constraint.yaml` | `k8snoprivescalation` |
| P4 - No latest tag | `gatekeeper/templates/no-latest-tag-template.yaml` | `gatekeeper/constraints/no-latest-tag-constraint.yaml` | `k8snolatesttag` |

> **Note:** P3 (resource limits) and P5 (privileged containers) were not implemented as Gatekeeper constraints because the three selected policies sufficiently demonstrate the admission control enforcement point. Adding more would follow the same pattern.

### Test Procedure

#### Step 1 - Create the kind Cluster

```powershell
kind create cluster --name pac-poc
```

#### Step 2 - Install Gatekeeper

```powershell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/v3.18.0/deploy/gatekeeper.yaml
kubectl wait --for=condition=Ready pod -l control-plane=controller-manager -n gatekeeper-system --timeout=90s
```

#### Step 3 - Patch Controller for CRD Generation (Required)

Gatekeeper v3.18.0 requires `--operation=generate` on the controller-manager to create CRDs from ConstraintTemplates. Without this flag, templates are accepted but their CRDs are never generated, and constraints cannot be created. See [Known Issues](#known-issues--troubleshooting) below.

Create `gatekeeper/patch-controller.json`:
```json
{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "manager",
          "args": [
            "--port=8443",
            "--logtostderr",
            "--exempt-namespace=gatekeeper-system",
            "--operation=webhook",
            "--operation=mutation-webhook",
            "--operation=generate",
            "--disable-opa-builtin={http.send}"
          ]
        }]
      }
    }
  }
}
```

Apply the patch:
```powershell
kubectl patch deployment gatekeeper-controller-manager -n gatekeeper-system --type=strategic --patch-file gatekeeper/patch-controller.json
kubectl rollout status deployment/gatekeeper-controller-manager -n gatekeeper-system --timeout=90s
```

#### Step 4 - Apply Templates and Constraints

```powershell
kubectl apply -f gatekeeper/templates/
# Wait for CRDs to register (~5-10 seconds)
kubectl apply -f gatekeeper/constraints/
```

#### Step 5 - Run the Test Script

```powershell
powershell -ExecutionPolicy Bypass -File scripts\gatekeeper-test.ps1
```

### Success Criteria

1. **Good manifest accepted** - `deployment-good.yaml` passes server-side dry-run with no rejection.
2. **Bad manifests rejected** - Each single-violation manifest is rejected with the correct violation message.
3. **Multi-violation rejected** - `deployment-multi-violation.yaml` is rejected with all applicable violations listed.
4. **Zero unexpected results** - The test script summary reports `Unexpected results: 0`.

### Actual Results (2026-03-25)

| Test | Manifest | Expected | Actual | Violation Message |
|---|---|---|---|---|
| 1 | `deployment-good.yaml` | ACCEPTED | **ACCEPTED** | - |
| 2 | `deployment-root.yaml` | REJECTED | **REJECTED** | Container 'app' must set securityContext.runAsNonRoot to true |
| 3 | `deployment-priv-escalation.yaml` | REJECTED | **REJECTED** | Container 'app' must set securityContext.allowPrivilegeEscalation to false |
| 4 | `deployment-latest-tag.yaml` | REJECTED | **REJECTED** | Container 'app' uses image 'nginx:latest' with ':latest' tag - use a pinned version |
| 5 | `deployment-multi-violation.yaml` | REJECTED | **REJECTED** | 3 violations: P1 (runAsNonRoot), P2 (allowPrivilegeEscalation), P4 (latest tag) |

**Result: 5/5 passed, 0 unexpected.**

Log: `results/logs/gatekeeper-test-20260325-152857.log`

---

## Known Issues & Troubleshooting

### Issue 1: ConstraintTemplate CRDs not generated (Gatekeeper v3.18.0)

**Symptom:**
- `kubectl apply -f gatekeeper/templates/` succeeds
- `kubectl get constrainttemplates` shows templates exist
- `kubectl get constrainttemplate <name> -o jsonpath='{.status.created}'` returns `false`
- `kubectl api-resources --api-group=constraints.gatekeeper.sh` returns no resources
- Controller logs show: `no matches for kind "K8sNoRoot" in version "constraints.gatekeeper.sh/v1beta1"`

**Root Cause:**
Starting with Gatekeeper v3.18.0, the `--operation=generate` flag (which triggers CRD creation from ConstraintTemplates) is **no longer enabled by default** on the controller-manager deployment. It was moved to the audit pod to avoid write contentions. This is documented in [GitHub issue #3967](https://github.com/open-policy-agent/gatekeeper/issues/3967).

**Fix:**
Add `--operation=generate` to the controller-manager deployment args:
```powershell
kubectl patch deployment gatekeeper-controller-manager -n gatekeeper-system `
  --type=strategic --patch-file gatekeeper/patch-controller.json
```

After patching, delete and re-apply ConstraintTemplates to trigger CRD generation.

### Issue 2: Rego v0 to v1 migration (Conftest policies)

**Symptom:**
Conftest 0.67.1 (OPA 1.14.1) rejects policies using the legacy `deny[msg] { ... }` syntax.

**Fix:**
All `.rego` files were updated to use OPA v1 syntax:
```rego
import rego.v1

deny contains msg if {
  # rule body
}
```

> **Note:** Gatekeeper ConstraintTemplates still use the classic `violation[{"msg": msg}] { ... }` syntax because Gatekeeper's embedded OPA version expects this format for the `violation` rule.

### Issue 3: PowerShell JSON quoting with kubectl

**Symptom:**
`kubectl patch` commands with inline JSON fail in PowerShell 5.1 due to curly-brace interpolation and quote escaping.

**Fix:**
Write the JSON patch to a file and use `--patch-file` instead of inline `-p`.

### Issue 4: Constraint API version (v1 vs v1beta1)

**Symptom:**
Confusion about whether constraint YAML files should use `constraints.gatekeeper.sh/v1` or `v1beta1`.

**Clarification:**
- **ConstraintTemplates** use `apiVersion: templates.gatekeeper.sh/v1` (the template CRD supports v1, v1alpha1, v1beta1)
- **Constraints** (the instances) use `apiVersion: constraints.gatekeeper.sh/v1beta1` because that is the version Gatekeeper v3.18.0 generates for constraint CRDs
- This is an internal Gatekeeper detail, not related to the Kubernetes `v1beta1` API deprecation
