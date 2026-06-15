# Policy-as-Code Enforcement in DevSecOps Pipelines

## Overview
This repository contains the proof of concept developed for the dissertation "Policy-as-Code Enforcement in DevSecOps Pipelines".

The PoC demonstrates how OPA/Rego policies can be used to enforce Kubernetes security rules at two points in a DevSecOps pipeline:
- CI validation using Conftest
- Kubernetes admission control using OPA Gatekeeper

## Main Components
- `docs/` - scope, policies, scenarios, evaluation plan, traceability, dataset catalogue, research question mapping, dissertation evaluation section, overhead results
- `policies/` - Rego policies (5 files, 9 deny rules, OPA v1 / Rego v1 syntax)
- `tests/` - 29 Kubernetes manifests (14 compliant + 15 non-compliant) covering 8 resource types
- `gatekeeper/` - Gatekeeper templates and constraints (P1, P2, P4)
- `.github/workflows/` - CI pipeline definitions
- `results/` - logs, screenshots, measurements, and summary CSV
- `scripts/` - test automation and overhead measurement scripts

## Research Questions
- **RQ1:** Can Policy-as-Code enforcement detect insecure Kubernetes configurations automatically?
- **RQ2:** Does multi-stage enforcement (CI + admission control) improve governance coverage?
- **RQ3:** Does admission control mitigate CI bypass risks?

## PoC Goal
To evaluate whether Policy-as-Code improves early detection and prevention of insecure Kubernetes configurations compared to a baseline without explicit policy enforcement. The evaluation uses 29 manifests (14 good, 15 bad) across 8 resource types, yielding 261 CI assertions with zero false positives and zero false negatives.

## Initial Policy Set
- P1: No root containers
- P2: No privilege escalation
- P3: Resource requests and limits required
- P4: No `latest` tag
- P5: No privileged containers

## Quick Start

### CI Validation (Conftest)

```powershell
# Install Conftest 0.67.1 (https://github.com/open-policy-agent/conftest/releases)
# Then run the test script:
powershell -ExecutionPolicy Bypass -File scripts\conftest-test.ps1
```

### Admission Control (Gatekeeper)

```powershell
# 1. Create the kind cluster
kind create cluster --name pac-poc

# 2. Install Gatekeeper v3.18.0
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/v3.18.0/deploy/gatekeeper.yaml
kubectl wait --for=condition=Ready pod -l control-plane=controller-manager -n gatekeeper-system --timeout=90s

# 3. REQUIRED: Patch controller-manager to enable CRD generation
#    (Gatekeeper v3.18.0 does not enable --operation=generate by default)
kubectl patch deployment gatekeeper-controller-manager -n gatekeeper-system `
  --type=strategic --patch-file gatekeeper/patch-controller.json
kubectl rollout status deployment/gatekeeper-controller-manager -n gatekeeper-system --timeout=90s

# 4. Apply templates and constraints
kubectl apply -f gatekeeper/templates/
# Wait ~10 seconds for CRDs to register
kubectl apply -f gatekeeper/constraints/

# 5. Run the test script
powershell -ExecutionPolicy Bypass -File scripts\gatekeeper-test.ps1
```

> **Important:** Step 3 is required for Gatekeeper v3.18.0+. Without `--operation=generate`, ConstraintTemplates will not create their CRDs and constraints will fail to apply. See `docs/evaluation-plan.md` for full details.

### GitHub Actions CI

The pipeline runs automatically on push/PR to `main`. See `.github/workflows/policy-check.yml`.

## Documentation Index

| Document | Description |
|---|---|
| [`docs/scope.md`](docs/scope.md) | PoC scope, objectives, and research questions (RQ1–RQ3) |
| [`docs/policies.md`](docs/policies.md) | Policy catalogue (P1–P5) with Rego details and enforcement points |
| [`docs/dataset.md`](docs/dataset.md) | Complete manifest catalogue (D-01–D-34) with classification and coverage |
| [`docs/scenarios.md`](docs/scenarios.md) | Unified scenario matrix (S01–S37) with expected and actual outcomes |
| [`docs/evaluation-plan.md`](docs/evaluation-plan.md) | Test procedures, tooling, and success criteria |
| [`docs/traceability-matrix.md`](docs/traceability-matrix.md) | Policy × manifest coverage matrices and detailed violation messages |
| [`docs/rq-mapping.md`](docs/rq-mapping.md) | Research question mapping with summary tables and per-manifest results |
| [`docs/dissertation-results.md`](docs/dissertation-results.md) | Dissertation evaluation section organised by RQ1/RQ2/RQ3 |
| [`docs/overhead-results.md`](docs/overhead-results.md) | Execution-time overhead measurements (CI and admission stages) |
| [`results/summary/manifest-results.csv`](results/summary/manifest-results.csv) | One-row-per-manifest result summary (29 rows) |