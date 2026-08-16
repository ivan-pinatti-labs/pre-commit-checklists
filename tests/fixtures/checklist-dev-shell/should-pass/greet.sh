#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

greet() {
  local name="${1:?name required}"
  echo "Hello, ${name}!"
}

greet "world"
