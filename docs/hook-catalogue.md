# Hook catalogue

Source data for every hook id exposed in
[`.pre-commit-hooks.yaml`](../.pre-commit-hooks.yaml). Each id dispatches
to a checklist file under [`checklists/`](../checklists/) (or, for the
two git-message hooks, directly to a script under
[`scripts/`](../scripts/)). See that file for exact upstream `rev:`
pins, which move independently of this table; see
[`docs/versioning.md`](versioning.md).

The "Matches" column is what you must add yourself: `.pre-commit-hooks.yaml`
does not bake in a `types:`/`files:` selector for most ids (two
exceptions are noted), so a bare `- id: checklist-json` with no selector
runs against **every** file pre-commit hands it, which is usually not
what you want. Every template in
[`templates/pre-commit-config/`](../templates/pre-commit-config/)
already applies the selector shown here; this table exists so you can
build your own selection from scratch.

<table>
  <tr>
    <th>Hook id</th>
    <th>Runs</th>
    <th>Matches</th>
    <th>Requires</th>
  </tr>
  <tr>
    <td><code>checklist-basic</code></td>
    <td>
      check-added-large-files (max 1024kb), check-case-conflict, check-docstring-first,
      check-illegal-windows-names, check-merge-conflict, check-symlinks, destroyed-symlinks,
      end-of-file-fixer, mixed-line-ending, trailing-whitespace
    </td>
    <td>
      all files (no selector needed)
    </td>
    <td>
      none
    </td>
  </tr>
  <tr>
    <td><code>checklist-spell</code></td>
    <td>
      cspell, config from <code>.cspell.json</code>
    </td>
    <td>
      all files cspell can read (no selector needed)
    </td>
    <td>
      <code>.cspell.json</code> at repo root
    </td>
  </tr>
  <tr>
    <td><code>checklist-markdown</code></td>
    <td>
      markdownlint-cli2, markdown-link-check
    </td>
    <td>
      <code>types: [markdown]</code>
    </td>
    <td>
      <code>.markdownlint.yaml</code> for markdownlint-cli2's own rules
    </td>
  </tr>
  <tr>
    <td><code>checklist-json</code></td>
    <td>
      check-json, Prettier
    </td>
    <td>
      <code>types: [json]</code>
    </td>
    <td>
      Node (Prettier runs via <code>language: node</code>)
    </td>
  </tr>
  <tr>
    <td><code>checklist-yaml</code></td>
    <td>
      check-yaml, yamllint, Prettier
    </td>
    <td>
      <code>types: [yaml]</code>
    </td>
    <td>
      <code>.yamllint.yml</code>; Node for Prettier
    </td>
  </tr>
  <tr>
    <td><code>checklist-toml</code></td>
    <td>
      check-toml
    </td>
    <td>
      <code>types: [toml]</code>
    </td>
    <td>
      none
    </td>
  </tr>
  <tr>
    <td><code>checklist-xml</code></td>
    <td>
      check-xml
    </td>
    <td>
      <code>types: [xml]</code>
    </td>
    <td>
      none
    </td>
  </tr>
  <tr>
    <td><code>checklist-security-credentials</code></td>
    <td>
      detect-private-key, detect-secrets
    </td>
    <td>
      all files (no selector needed)
    </td>
    <td>
      <code>.secrets.baseline</code> at repo root, <code>scripts/install.sh</code> generates one
    </td>
  </tr>
  <tr>
    <td><code>checklist-git-valid-branches</code></td>
    <td>
      <code>scripts/check-branch-name.sh</code>
    </td>
    <td>
      not file-based: <code>pass_filenames: false</code>, <code>always_run: true</code>
    </td>
    <td>
      none
    </td>
  </tr>
  <tr>
    <td><code>checklist-git-commit-msg</code></td>
    <td>
      <code>scripts/check-commit-msg.sh</code>
    </td>
    <td>
      <code>stages: [commit-msg]</code>, <code>files: ^\.git/COMMIT_EDITMSG$</code>
    </td>
    <td>
      <code>default_install_hook_types</code> must include <code>commit-msg</code>
    </td>
  </tr>
  <tr>
    <td><code>checklist-git-protected-branches</code></td>
    <td>
      no-commit-to-branch, pattern <code>(?i)(develop|staging|main|master)</code>
    </td>
    <td>
      not file-based: <code>pass_filenames: false</code>, <code>always_run: true</code>
    </td>
    <td>
      none
    </td>
  </tr>
  <tr>
    <td><code>checklist-github-actions</code></td>
    <td>
      actionlint-docker
    </td>
    <td>
      <code>files: ^\.github/</code>
    </td>
    <td>
      Docker (actionlint-docker runs in a container)
    </td>
  </tr>
  <tr>
    <td><code>checklist-dev-dotenv</code></td>
    <td>
      dotenv-linter
    </td>
    <td>
      <code>files: '(^|/)\.env(\..+)?$'</code>
    </td>
    <td>
      none
    </td>
  </tr>
  <tr>
    <td><code>checklist-dev-editorconfig</code></td>
    <td>
      editorconfig-checker
    </td>
    <td>
      all files subject to <code>.editorconfig</code> (no selector needed)
    </td>
    <td>
      <code>.editorconfig</code> at repo root
    </td>
  </tr>
  <tr>
    <td><code>checklist-dev-shell</code></td>
    <td>
      check-executables-have-shebangs, check-shebang-scripts-are-executable,
      shellcheck (<code>--severity=error</code>), shfmt (<code>--indent 2</code>)
    </td>
    <td>
      <code>types: [shell]</code> (the hook's own <code>.pre-commit-hooks.yaml</code> entry
      additionally bakes in <code>files: \.(sh|bash)$</code>)
    </td>
    <td>
      none
    </td>
  </tr>
  <tr>
    <td><code>checklist-dev-python</code></td>
    <td>
      check-ast, check-builtin-literals, debug-statements,
      name-tests-test (<code>--django</code>), requirements-txt-fixer,
      ruff-check (<code>--fix</code>), ruff-format
    </td>
    <td>
      <code>files: '(\.py$|(^|/)requirements\.txt$)'</code>
    </td>
    <td>
      none
    </td>
  </tr>
  <tr>
    <td><code>checklist-dev-terraform</code></td>
    <td>
      terraform-fmt, terraform-validate, tflint
    </td>
    <td>
      <code>files: \.tf$</code>
    </td>
    <td>
      Terraform CLI
    </td>
  </tr>
  <tr>
    <td><code>checklist-dev-javascript</code></td>
    <td>
      biome-check (<code>--indent-style=space --indent-width=2</code>)
    </td>
    <td>
      <code>types: [javascript]</code>
    </td>
    <td>
      Node (biome-check runs via <code>language: node</code>)
    </td>
  </tr>
  <tr>
    <td><code>checklist-dev-typescript</code></td>
    <td>
      biome-check (<code>--indent-style=space --indent-width=2</code>)
    </td>
    <td>
      <code>files: \.ts$</code>
    </td>
    <td>
      Node (biome-check runs via <code>language: node</code>)
    </td>
  </tr>
  <tr>
    <td><code>checklist-dev-docker</code></td>
    <td>
      hadolint-docker
    </td>
    <td>
      <code>types: [dockerfile]</code>
    </td>
    <td>
      Docker (hadolint-docker runs in a container)
    </td>
  </tr>
</table>

## Why the selector matters

Two defects in an earlier version of this checklist set came from
getting a selector wrong, not from the underlying tool: a
`types: [json]` selector on the dotenv checklist meant it never matched
a `.env` file (dotenv files aren't typed `json`), and `types_or: [python]`
combined with `files: ^requirements\.txt$` on the Python checklist
resolved to "a Python file literally named `requirements.txt`": pre-commit
ANDs `types`/`types_or` with `files`, it does not OR them. Both are
fixed in the table above and in every shipped template. If you write
your own selector for a hook id, prefer one `files:` regex over
combining `types:`/`types_or:` with `files:` unless you have checked
what the AND actually resolves to.

## Pin `stages:` too, if you install more than the pre-commit stage

`checklist-git-commit-msg` is the one id here that isn't meant to run at
the `pre-commit` git stage: it needs `stages: [commit-msg]`. If your
`default_install_hook_types` includes anything beyond `pre-commit`
(`commit-msg`, `pre-push`, ...), every *other* hook id also needs an
explicit `stages: [pre-commit]`, or pre-commit will run it again at
each of those other stages too. That's wasted work at best; at worst,
a hook re-run outside the context it expects can fail outright: cspell
does exactly this, exiting non-zero on a commit-msg-stage invocation
where it is handed zero matching files. Every shipped template that
enables `commit-msg` (`recommended.yaml`, `full.yaml`) already sets
`stages: [pre-commit]` on every hook that needs it; keep doing that if
you add more hooks of your own to either file.
