# Policy P3: CPU and memory requests and limits must be defined
# Ensures containers declare resources.requests and resources.limits
# for both cpu and memory.

package main

import rego.v1

deny contains msg if {
  container := input.spec.template.spec.containers[_]
  res := object.get(container, "resources", {})
  req := object.get(res, "requests", {})
  not req.cpu
  msg := sprintf("Container '%s' must define resources.requests.cpu", [container.name])
}

deny contains msg if {
  container := input.spec.template.spec.containers[_]
  res := object.get(container, "resources", {})
  req := object.get(res, "requests", {})
  not req.memory
  msg := sprintf("Container '%s' must define resources.requests.memory", [container.name])
}

deny contains msg if {
  container := input.spec.template.spec.containers[_]
  res := object.get(container, "resources", {})
  lim := object.get(res, "limits", {})
  not lim.cpu
  msg := sprintf("Container '%s' must define resources.limits.cpu", [container.name])
}

deny contains msg if {
  container := input.spec.template.spec.containers[_]
  res := object.get(container, "resources", {})
  lim := object.get(res, "limits", {})
  not lim.memory
  msg := sprintf("Container '%s' must define resources.limits.memory", [container.name])
}
