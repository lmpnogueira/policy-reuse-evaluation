# Policy P1: Containers must not run as root
# Ensures securityContext.runAsNonRoot is explicitly set to true.

package main

import rego.v1

deny contains msg if {
  container := input.spec.template.spec.containers[_]
  sc := object.get(container, "securityContext", {})
  not sc.runAsNonRoot == true
  msg := sprintf("Container '%s' must set securityContext.runAsNonRoot to true", [container.name])
}
