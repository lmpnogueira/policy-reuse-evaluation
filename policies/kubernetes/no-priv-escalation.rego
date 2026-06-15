# Policy P2: Privilege escalation must be disabled
# Ensures securityContext.allowPrivilegeEscalation is explicitly set to false.

package main

import rego.v1

deny contains msg if {
  container := input.spec.template.spec.containers[_]
  sc := object.get(container, "securityContext", {})
  not sc.allowPrivilegeEscalation == false
  msg := sprintf("Container '%s' must set securityContext.allowPrivilegeEscalation to false", [container.name])
}
