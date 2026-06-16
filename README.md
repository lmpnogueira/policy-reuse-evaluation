# Reusing Policy-as-Code Across CI/CD and Kubernetes Admission Control

This repository contains the replication package associated with the paper:

> **Reusing Policy-as-Code Across CI/CD and Kubernetes Admission Control: An Empirical Assessment of Governance Consistency**

The repository provides all artefacts required to reproduce the experimental evaluation presented in the paper, including policy definitions, Kubernetes manifests, CI workflows, admission-control configurations, experimental scenarios, and evaluation results.

## Overview

Policy-as-Code (PaC) is increasingly used to automate governance, security, and compliance enforcement in cloud-native software delivery pipelines. However, governance requirements are often implemented separately across different enforcement stages, increasing maintenance effort and creating opportunities for policy drift.

This study evaluates a reusable multi-stage Policy-as-Code enforcement model in which the same Open Policy Agent (OPA) Rego policies are executed during:

* Continuous Integration (CI) validation using Conftest;
* Kubernetes admission control using OPA Gatekeeper.

The evaluation investigates:

1. Automatic detection of insecure Kubernetes configurations;
2. Governance assurance through multi-stage enforcement;
3. Mitigation of CI bypass scenarios through Kubernetes admission control.

## Repository Structure

```text
.
├── policies/                # Rego policy definitions
├── manifests/               # Kubernetes manifests used in the evaluation
├── gatekeeper/              # Gatekeeper templates and constraints
├── workflows/               # GitHub Actions workflows
├── scenarios/               # Experimental scenarios
├── results/                 # Validation outputs and evaluation results
├── traceability/            # Research-question traceability artefacts
└── documentation/           # Supporting documentation
```

The exact directory names may vary slightly depending on the repository version.

## Experimental Dataset

The evaluation dataset comprises:

| Item                      | Value |
| ------------------------- | ----- |
| Kubernetes manifests      | 29    |
| Experimental scenarios    | 37    |
| Kubernetes resource types | 8     |
| Governance policies       | 5     |
| Rego deny rules           | 9     |
| Policy assertions         | 261   |

The dataset includes:

* compliant workloads;
* negative-control resources;
* single-policy violations;
* multi-policy violations;
* dedicated CI bypass scenarios.

## Governance Policies

The evaluation considers five representative Kubernetes governance policies:

| Policy ID | Description                           |
| --------- | ------------------------------------- |
| P1        | No Root Execution                     |
| P2        | No Privilege Escalation               |
| P3        | Resource Requests and Limits Required |
| P4        | No Mutable Image Tags (`latest`)      |
| P5        | No Privileged Containers              |

These policies are implemented using reusable Rego definitions and evaluated across multiple enforcement stages.

## Reproducing CI Validation

CI validation is performed using Conftest.

Example:

```bash
conftest test manifests/
```

Policy violations produce non-zero exit codes and validation reports suitable for CI/CD integration.

## Reproducing Admission-Control Validation

Admission-control validation is performed using OPA Gatekeeper.

Deploy Gatekeeper to a Kubernetes cluster and apply the provided templates and constraints:

```bash
kubectl apply -f gatekeeper/
```

Validation can then be exercised using:

```bash
kubectl apply -f manifests/example.yaml
```

or:

```bash
kubectl apply --dry-run=server -f manifests/example.yaml
```

depending on the scenario being reproduced.

## Research Questions

The experimental evaluation addresses the following research questions:

**RQ1:** Can Policy-as-Code enforcement detect insecure Kubernetes configurations automatically?

**RQ2:** Does multi-stage enforcement strengthen governance assurance compared with reliance on a single enforcement boundary?

**RQ3:** Can Kubernetes admission control mitigate governance failures caused by CI bypass scenarios?

## Replication Artefacts

This repository includes:

* reusable Rego policies;
* Kubernetes manifests;
* Gatekeeper constraints;
* CI workflows;
* experimental scenarios;
* validation outputs;
* traceability matrices;
* supporting documentation.

These artefacts are intended to support transparency, reproducibility, and independent verification of the results reported in the paper.

## Citation

If you use this repository in academic work, please cite:

```bibtex
[paper citation to be added after publication]
```

## License

This repository is released for research and educational purposes. Please refer to the repository license for usage conditions.
