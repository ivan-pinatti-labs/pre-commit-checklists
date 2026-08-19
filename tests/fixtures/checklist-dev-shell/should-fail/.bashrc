# shellcheck shell=bash
# Same extensionless shell dotfile, with a shellcheck error in it: `local`
# outside a function, matching should-fail/greet.sh. Proves the hook now
# reaches this file rather than skipping it.

alias ll='ls -alF'

local name="not inside a function"
echo "Hello, ${name}!"
