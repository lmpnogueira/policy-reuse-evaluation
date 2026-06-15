# Policy P4: Container images must not use the ":latest" tag
# Ensures every container image has an explicit, pinned version tag.

package main

import rego.v1

deny contains msg if {
  container := input.spec.template.spec.containers[_]
  image := object.get(container, "image", "")
  endswith(image, ":latest")
  msg := sprintf("Container '%s' uses image '%s' with ':latest' tag - use a pinned version instead", [container.name, image])
}

deny contains msg if {
  container := input.spec.template.spec.containers[_]
  image := object.get(container, "image", "")
  image != ""
  not contains(image, ":")
  msg := sprintf("Container '%s' uses image '%s' without a tag - use a pinned version instead", [container.name, image])
}
