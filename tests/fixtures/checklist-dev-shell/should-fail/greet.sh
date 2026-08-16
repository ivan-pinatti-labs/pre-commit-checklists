#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

local name="not inside a function"
echo "Hello, ${name}!"
