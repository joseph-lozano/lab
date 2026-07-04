Build me a git repository called `lab` that provisions a reproducible, disposable cloud dev box.

Use my original architecture and ordering, but apply the corrections below. These corrections override any conflicting text in the rest of this prompt, even when the original text says a decision was “resolved,” “verified,” or “locked.” Ask only when something is genuinely ambiguous.

## Corrections and accuracy requirements

### hk / Pkl / gitleaks

Correct the hk decision:

* hk should be installed via the repo-local `mise.toml`.
* gitleaks should be installed via the repo-local `mise.toml`.
* Do **not** require the external `pkl` CLI by default. Current hk uses its built-in Rust `pklr` backend by default.
* Only add `pkl` to repo-local `mise.toml` if we explicitly opt into `HK_PKL_BACKEND=pkl`.
* The default implementation should rely on hk’s built-in backend and should not set `HK_PKL_BACKEND=pkl`.
* `hk.pkl` must still use the current `amends "package://github.com/jdx/hk/releases/download/vX.Y.Z/..."` schema, pinned to the hk version in `mise.toml`.
* Use hk’s gitleaks builtin if available in the pinned hk version; otherwise fail the build with a clear comment saying the pinned hk version must be updated or the hook schema adjusted.
* README local setup should say: `mise install && hk install`.

### 1Password CLI install and verification

On Ubuntu/Debian, install the official 1Password CLI package named `1password-cli`, which provides the `op` binary.

Bootstrap must:

1. Add the official 1Password apt signing key and repository.
2. Configure the expected debsig policy/keyring steps from the official 1Password Linux install instructions.
3. `apt install 1password-cli`.
4. Verify with service-account-compatible commands:

   * `op user get --me`
   * and a read/list operation scoped to the configured `lab` vault, such as reading a known required item or listing items in that vault.
5. Do not rely on undocumented or unverified commands such as `op whoami` unless the implementation verifies they work with service-account auth.

Every command that uses 1Password service-account auth must either:

* source `OP_SERVICE_ACCOUNT_TOKEN` from the relevant on-disk token file inside the shell command, or
* pass it through Ansible `environment:` with `no_log: true`.

Prefer sourcing from the on-disk token file where possible.

### GitHub CLI auth storage

Keep the design that `gh auth login --with-token` is allowed and `gh auth setup-git` is forbidden.

Correct the storage invariant:

* `gh` may store credentials in an OS credential store when available.
* On a headless VPS without a usable credential store, expect plaintext fallback, commonly under `~/.config/gh/hosts.yml`.
* After `gh auth login --with-token`, run `gh auth status` as an unmasked verification step so the README and logs show where gh says the credential is stored.
* Ensure `~/.config/gh/hosts.yml` is `0600` if it exists.
* README security notes must describe gh and agent credential stores as “additional local credential stores that may contain cleartext tokens, depending on the CLI and credential-store availability.”

Never run `gh auth setup-git`; it writes Git credential-helper configuration that fights the chezmoi-owned `~/.gitconfig`.

### Git credential helper

The chezmoi-managed Git credential helper should emit both username and password for GitHub HTTPS credentials.

The helper should output at least:

```text
username=x-access-token
password=<PAT read from 1Password>
```

It must read `OP_SERVICE_ACCOUNT_TOKEN` from the USER token file, not from shell startup, and then run:

```sh
op read "op://<lab-vault>/<github-pat-item>/<token-field>"
```

Do not have Ansible write Git credential config. The helper stanza belongs only in `home/dot_gitconfig.tmpl`.

### Tailscale SSH policy

The README Tailscale admin-side prerequisite must include both:

1. Network access permission to the tagged node.
2. A Tailscale SSH rule.

Do not use `autogroup:nonroot` in the example when the destination is a tagged node unless the intent is to allow every non-root account name. This lab should permit the configured non-root lab user only.

Example shape:

```jsonc
{
  "tagOwners": {
    "tag:lab": ["autogroup:admin"]
  },

  "grants": [
    {
      "src": ["autogroup:member"],
      "dst": ["tag:lab"],
      "ip": ["*"]
    }
  ],

  "ssh": [
    {
      "action": "accept",
      "src": ["autogroup:member"],
      "dst": ["tag:lab"],
      "users": ["<configured-username>"]
    }
  ]
}
```

The README must state:

* A pre-authorized tagged auth key alone does not grant Tailscale SSH access.
* SSH access also requires an SSH policy rule.
* Root login is intentionally not permitted by the Tailscale SSH ACL.
* Root-level debugging happens by connecting as the non-root user and using `sudo`.
* Break-glass is the provider console; a truly wedged box should be rebuilt.

### Tailscale ephemeral nodes, auth keys, and reconnect unit

Use precise wording:

* Ephemeral nodes are usually removed shortly after going offline, commonly around 30–60 minutes.
* A re-registered node may get a different Tailscale IP.
* Therefore, output and documentation should steer the user to the MagicDNS hostname, not a memorized IP.
* Pass `--hostname={{ hostname }}` to `tailscale up`.
* Auth keys expire between 1 and 90 days. Reusable keys still expire. The README rotation runbook must include updating the Tailscale auth key item in 1Password before expiry.
* Tagged devices normally have node-key expiry disabled by default, but the auth key is still needed for rebuilds and for recovery if the machine must re-register.

The reconnect unit must:

* be a systemd oneshot unit;
* be `WantedBy=multi-user.target`;
* use `Wants=network-online.target`;
* use `After=network-online.target tailscaled.service`;
* handle logged-out/stopped/non-running Tailscale states without assuming `tailscale status` exits zero;
* preferably inspect `tailscale status --json` when available;
* pass the full intended `tailscale up` flag set every time, because Tailscale `up` flags are not persisted across runs;
* no-op when already connected as intended;
* read the Tailscale auth key from 1Password using `/root/.config/lab/op-token`.

### Tailscale direct UDP

Keep `allow_direct_udp` default false.

When true, allow inbound UDP 41641 for Tailscale direct connections. Document that 41641 is the default Tailscale UDP port; if the implementation ever changes the tailscaled port with `--port`, the firewall rule must change accordingly.

### SSH daemon masking

On Ubuntu, disable/mask `ssh.service`. Also mask `sshd.service` if that unit exists.

Do not refer to masking `openssh-server` as a systemd unit; `openssh-server` is the package name.

Add a comment explaining:

* Tailscale SSH does not require the normal OpenSSH daemon for Tailscale-IP SSH.
* Public/plain SSH is intentionally disabled after Tailscale is confirmed working.
* Public SSH lockdown must happen only after Tailscale connectivity is confirmed.

### Ubuntu 26.04 TODO

Keep Ubuntu 24.04 LTS as the base OS.

Add a TODO:

* Re-evaluate migration to Ubuntu 26.04 LTS after the first 26.04.1 point release in August 2026 and after required vendor apt repositories publish `resolute` targets.
* Treat sudo-rs/uutils/Rust-userland changes as automation compatibility risks to test, not as a guaranteed full replacement of GNU userland tools.

### mise system packages

Keep the split:

* `mise install` for user tools as the non-root user.
* `mise system install --yes` for OS packages with elevation.

Do not assume `mise system install --yes` will merely print a manual command instead of prompting. Run it in a way that cannot hang unattended:

* use Ansible privilege escalation where appropriate;
* set the needed environment explicitly;
* keep a commented plain-apt fallback for `[system.packages]` in case the pinned mise version or schema changes.

Pin mise to a known-good version and verify that the pinned version supports the configured system-package syntax and `mise system install`.

### OMP validation

Implement the OMP setup as originally requested, but treat the following as build-time assertions that must be verified against the installed/pinned OMP version:

* `models.yml` is the modern provider config format.
* `api: openai-codex-responses` is a valid API type for custom OpenAI Codex providers.
* `apiKey: "!op read op://<lab-vault>/openai/api-key"` is valid command-secret syntax.
* OMP’s Bun dependency is runtime-only when installed from the selected mise backend.

If any assertion fails, do not silently substitute a different agent architecture. Instead:

* add a clear TODO/comment showing the exact failing command/output;
* preserve the placeholder provider structure;
* keep real secrets out of git.

The OpenAI key remains a 1Password reference only, never a committed value.

### Cloud-init metadata security note

The README security note must plainly say:

* The service-account token appears in cloud-init user-data.
* On many cloud providers, user-data may be readable from the instance by local processes via the metadata service or local cloud-init artifacts.
* This is an accepted bootstrap tradeoff.
* The service account must be read-only and scoped only to the `lab` vault.
* Rotation means replacing both persisted OP token files or rebuilding the box.

### First-boot ordering remains mandatory

Preserve this ordering:

1. cloud-init or `scripts/bootstrap.sh`
2. `ansible-pull`
3. `base`
4. `onepassword`
5. `tailscale`
6. `security`
7. `user`
8. `chezmoi`
9. `mise`
10. `workspace`

Key ordering constraints:

* `fish` is installed by the base role before the user role sets it as the login shell.
* hostname is set before Tailscale joins.
* Tailscale is confirmed before firewall lockdown and public SSH shutdown.
* the non-root USER op-token exists before chezmoi/future templates need it.
* chezmoi runs before private work repo clones so the Git credential helper exists.
* mise runs before workspace setup that needs `gh`, `omp`, and other tools.
* `gh auth setup-git` is never run.
* all scripts and Ansible shell tasks stay bash/POSIX; fish is interactive-only.

### Public repo hygiene

The `lab` repo is public.

README must warn that all committed files are public, including:

* `ansible/group_vars/all.yml`;
* the chezmoi source under `home/`;
* repo-local `mise.toml`;
* `hk.pkl`;
* work repo names/URLs if committed.

If private repo names are sensitive, document the alternative of moving the work-repo list into 1Password, but do not build that second code path unless trivial.

### Required implementation output

Start by showing the implementation plan before writing files.

Then lay out:

* repo skeleton;
* `.chezmoiroot`;
* repo-local `mise.toml`;
* `hk.pkl`;
* `.gitignore`;
* `home/` chezmoi source;
* `cloud-init/user-data.yaml.tmpl`;
* `scripts/bootstrap.sh`;
* `ansible/` config;
* `group_vars/all.yml`;
* roles in first-boot order.

Keep all user-specific values parameterized in `group_vars/all.yml` or clearly marked templates. Keep all secrets out of git. Templates may contain 1Password references only.

