# Overhead Measurement Results

> This document reports the execution-time overhead introduced by
> Policy-as-Code enforcement at both the CI and admission-control stages.
> The measurements are intended to provide a practical (not statistically
> rigorous) characterisation of the cost of policy evaluation within the
> proof-of-concept scope.

---

## 1. Method

Each operation was executed **20 times** on the local development workstation.
The first execution was discarded as a warm-up run to exclude one-time
costs (process startup, Rego compilation caching). Wall-clock time was
measured using `System.Diagnostics.Stopwatch` in PowerShell 5.1. Results
are reported as average, minimum, maximum, and standard deviation across
the remaining **19 runs**.

**Environment:**

| Component | Value |
|---|---|
| OS | Windows 10/11 |
| Shell | PowerShell 5.1 |
| Conftest | 0.67.1 (OPA 1.14.1) |
| kubectl | 1.32.3 |
| Cluster | kind v0.27.0 (K8s 1.32.2, local Docker) |
| Gatekeeper | 3.18.0 |
| Script | `scripts/measure-overhead.ps1` |
| Manifests evaluated | 29 (14 good + 15 bad) |
| Policies | 5 (9 deny rules) |

**Operations measured:**

| ID | Operation | What It Represents |
|---|---|---|
| M1 | `kubectl apply --dry-run=client` (good manifest) | Baseline: YAML parsing and client-side validation with no policy engine |
| M2 | `conftest test tests/good/ tests/bad/` (all 29 manifests) | CI-stage policy evaluation: full Conftest run against the complete dataset |
| M3 | `kubectl apply --dry-run=server` (good manifest) | Admission control: compliant manifest passes through Gatekeeper webhook |
| M4 | `kubectl apply --dry-run=server` (bad manifest) | Admission control: non-compliant manifest rejected by Gatekeeper webhook |

---

## 2. Results

> **Note:** Replace the placeholder values below with the actual measurements
> from `results/measurements/overhead-<timestamp>.csv` after running the
> measurement script.

### 2.1 Raw Results

| ID | Operation | N | Avg (ms) | Min (ms) | Max (ms) | SD (ms) |
|---|---|---|---|---|---|---|
| M1 | `kubectl --dry-run=client` (no policy) | 19 | 56.8 | 52.4 | 61.6 | 1.9 |
| M2 | `conftest test` (all 29 manifests) | 19 | 56.3 | 53.7 | 59.6 | 1.7 |
| M3 | `kubectl --dry-run=server` (allowed) | 19 | _pending_ | _pending_ | _pending_ | _pending_ |
| M4 | `kubectl --dry-run=server` (rejected) | 19 | _pending_ | _pending_ | _pending_ | _pending_ |

> M3 and M4 require Docker Desktop and the kind cluster with Gatekeeper.
> Run `scripts/measure-overhead.ps1` again after starting the cluster to
> collect these values.

### 2.2 Derived Metrics

| Metric | Value | Derivation |
|---|---|---|
| Conftest overhead vs. baseline | −0.5 ms | M2 avg (56.3) − M1 avg (56.8) |
| Conftest overhead factor | 1.0× | M2 avg / M1 avg |
| Admission rejection delta | _pending_ | M4 avg - M3 avg |

---

## 3. Interpretation

### 3.1 CI-Stage Overhead (M1 vs. M2)

Conftest evaluation of 29 manifests against 9 deny rules completed in an
average of 56.3 ms (SD 1.7 ms), compared to 56.8 ms (SD 1.9 ms) for a
baseline `kubectl --dry-run=client` validation — a difference of −0.5 ms
(overhead factor: 1.0×). The negative delta and overlapping standard
deviations confirm that the policy evaluation time is indistinguishable
from the baseline within measurement noise. In the context of a CI pipeline
where typical job durations are measured in tens of seconds (repository
checkout, dependency installation, image build, test suite), an additional
sub-millisecond cost for policy evaluation is operationally negligible.

The result is consistent with Conftest's architecture: both `kubectl` and
`conftest` invoke a Go binary that parses YAML and performs in-memory
evaluation. The Rego compilation and evaluation step adds minimal overhead
for a small policy set (5 files, 9 rules).

### 3.2 Admission-Stage Overhead (M3 vs. M4)

_Pending: requires Docker Desktop and kind cluster with Gatekeeper. Re-run
`scripts/measure-overhead.ps1` after starting the cluster._

<!-- Expected interpretation:
The difference between an allowed request (M3) and a rejected request (M4)
represents the additional processing time for Gatekeeper to evaluate
constraints and generate violation messages. Both M3 and M4 include network
round-trip to the kind cluster and the Gatekeeper webhook call, so the
absolute values will be higher than the client-only baseline (M1). The
rejection delta itself is expected to be small relative to the total
round-trip time.
-->

### 3.3 Limitations

- Measurements were taken on a single developer workstation with a local
  kind cluster. Network latency to a remote cluster would dominate
  admission-control timings in a production environment.
- The dataset contains 29 manifests with 5 policies (9 rules). Overhead
  may scale differently with larger policy sets or manifest volumes.
- The first of 20 executions was discarded as a warm-up run to exclude
  one-time costs (process startup, Rego compilation caching).
- The 19-run sample size is sufficient for a practical PoC
  characterisation but does not support statistical significance claims.

---

## 4. CSV Data

Raw measurement data is stored in `results/measurements/overhead-20260421-123458.csv`
with the following schema:

```
Id,Operation,Iterations,AvgMs,MinMs,MaxMs,SdMs,AllMs
M1,"kubectl --dry-run=client (no policy)",19,56.8,52.4,61.6,1.9,<r1>;...;<r19>
M2,"conftest test (all manifests)",19,56.3,53.7,59.6,1.7,<r1>;...;<r19>
M3,"kubectl --dry-run=server (allowed)",19,<pending>
M4,"kubectl --dry-run=server (rejected)",19,<pending>
```

The `AllMs` column contains the individual run times separated by semicolons,
allowing full reproducibility analysis.

---

## 5. Reproduction

```powershell
# From the repository root:
powershell -ExecutionPolicy Bypass -File scripts\measure-overhead.ps1

# To change the number of iterations (default: 20):
powershell -ExecutionPolicy Bypass -File scripts\measure-overhead.ps1 -Iterations 30
```

Prerequisites:
- `conftest` in PATH (for M2)
- `kubectl` in PATH, kind cluster running (for M1, M3, M4)
- Gatekeeper installed with constraints applied (for M3, M4)
