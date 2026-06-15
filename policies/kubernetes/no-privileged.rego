# Policy P5: Containers must not run in privileged mode
# Ensures securityContext.privileged is not set to true.

package main

import rego.v1

deny contains msg if {
  container := input.spec.template.spec.containers[_]
  sc := object.get(container, "securityContext", {})
  sc.privileged == true
  msg := sprintf("Container '%s' must not run in privileged mode", [container.name])
}
