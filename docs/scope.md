# PoC Scope

## Title
Policy-as-Code Enforcement in DevSecOps Pipelines

## PoC Objective
This proof of concept aims to design, implement, and evaluate a Policy-as-Code enforcement approach for DevSecOps pipelines. The PoC will use OPA/Rego to enforce a limited set of security policies over Kubernetes manifests at two pipeline stages: CI validation and Kubernetes admission control.

## Problem Statement
DevSecOps pipelines often lack consistent, automated, and auditable enforcement of security policies across the software delivery lifecycle. In practice, insecure configurations may pass through CI/CD pipelines because security rules are applied manually, inconsistently, or too late. This creates governance gaps, weak traceability, and higher remediation cost.

## Scope
The PoC includes:
- Kubernetes manifests as the only governed artefact type
- OPA/Rego as the policy language
- Conftest for policy validation in CI
- OPA Gatekeeper for policy enforcement at Kubernetes admission control
- A GitHub repository containing policies, manifests, tests, and pipeline configuration
- Five security policies that are machine-enforceable and relevant to Kubernetes deployment security
- Controlled compliant and non-compliant scenarios
- Baseline vs PoC comparison

## Out of Scope
The PoC does not include:
- Terraform, Dockerfiles, Helm charts, or SBOM validation
- Runtime monitoring or drift detection
- Secrets scanning
- Container image vulnerability scanning
- SIEM, SOAR, or external governance platforms
- Full regulatory compliance mapping to ISO 27001, GDPR, or PCI-DSS
- Multi-cloud or production-grade deployment
- Enterprise-scale policy lifecycle management

## Enforcement Points
The PoC implements enforcement at two points:
1. CI validation using Conftest and OPA/Rego
2. Kubernetes admission control using OPA Gatekeeper

## Research Objective Alignment
This PoC supports:
- problem interpretation
- design of a technical solution
- implementation of the solution
- experimental evaluation of the solution
- critical analysis of results

## Expected Contribution
The PoC is expected to contribute:
- a small but reproducible reference implementation
- a structured mapping from high-level policy requirements to machine-enforceable rules
- evidence on the effectiveness of early and multi-stage policy enforcement in DevSecOps pipelines

## Success Criteria
The PoC is considered successful if:
- all selected policies are implemented and versioned
- compliant manifests pass CI and admission control
- non-compliant manifests are blocked in CI
- non-compliant manifests are rejected at admission when applied directly
- results are collected for all scenarios
- baseline and PoC behavior can be compared
- policy checks introduce acceptable overhead for the PoC context

## Main Research Questions
RQ1: Can Policy-as-Code enforcement detect insecure Kubernetes configurations automatically?

RQ2: Does multi-stage enforcement (CI + admission control) improve governance coverage?

RQ3: Does admission control mitigate CI bypass risks?