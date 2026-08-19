# shellcheck shell=bash
# An extensionless shell dotfile. identify tags this `shell`, but the
# checklist-dev-shell hook id used to bake in `files: \.(sh|bash)$`, which
# ANDed with a consumer's `types: [shell]` and dropped this file silently.
# Sourced, not executed, so it carries no shebang and is not executable.

alias ll='ls -alF'

parse_git_branch() {
  git rev-parse --abbrev-ref HEAD 2>/dev/null
}
