# lab

`lab` provisions a reproducible, disposable Ubuntu cloud dev box. The repo is designed to be public: every committed file is assumed public, including `ansible/group_vars/all.yml`, the chezmoi source under `home/`, repo-local `mise.toml`, `hk.pkl`, and any committed work repository names or URLs. Keep secrets out of git; templates may contain 1Password references only.

## Architecture and first-boot order

The first boot path is intentionally linear:

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

Ordering constraints enforced by `ansible/site.yml`:

- `fish` is installed by the `base` role before the `user` role sets it as the login shell.
- The hostname is set before Tailscale joins.
- Tailscale is confirmed before firewall lockdown; SSH remains available only on the Tailscale interface.
- The non-root user token file exists before chezmoi/future templates need it.
- Chezmoi runs before private work repo clones so the Git credential helper exists.
- Mise runs before workspace setup that needs `gh`, `omp`, and other tools.
- `gh auth setup-git` is never run.
- All scripts and Ansible shell tasks stay bash/POSIX; fish is interactive-only.

## Local setup

Install repo tools and hooks:

```sh
mise install && hk install
```

Repo-local `mise.toml` installs only local repo/coding hook tooling: `hk`, `gitleaks`, `shellcheck`, and `usage`. Box user tools live in the chezmoi-managed `home/dot_config/mise/config.toml`, which installs `gh` and `omp` for the non-root lab user. `hk.pkl` uses hk's built-in Rust `pklr` backend by default. This repo does not set `HK_PKL_BACKEND=pkl` and does not require the external `pkl` CLI unless you explicitly opt into that backend; if you do, add `pkl` to repo-local `mise.toml` at the same time.

On the box, Ansible applies chezmoi before the `mise` role, so `/home/<user>/.config/mise/config.toml` exists before Ansible runs `mise install` as the non-root user. OS packages are installed by the `base` role via apt; re-enable `mise system install --yes` only after the pinned mise version supports the selected `[system.packages]` schema without breaking repo-local `mise install`.

## Cloud bootstrap

Render `cloud-init/user-data.yaml.tmpl` with your cloud provider/user-data tooling, or copy the repo to a fresh Ubuntu 24.04 LTS host and run:

```sh
sudo LAB_REPO_URL=https://github.com/you/lab.git \
  OP_SERVICE_ACCOUNT_TOKEN='...' \
  bash scripts/bootstrap.sh
```

The bootstrap token must be a read-only 1Password service-account token scoped only to the configured `lab` vault. Rotation means replacing both persisted OP token files (`/root/.config/lab/op-token` and `/home/<user>/.config/lab/op-token`) or rebuilding the box.

### Cloud-init metadata security

The service-account token appears in cloud-init user-data. On many cloud providers, user-data may be readable from the instance by local processes via the metadata service or local cloud-init artifacts. This is an accepted bootstrap tradeoff. Scope the service account read-only to the `lab` vault.

## Required 1Password items

Configure names/fields in `ansible/group_vars/all.yml`:

- Tailscale auth key item and field.
- GitHub PAT item and field.
- Optional Codex subscription item and field for OMP.

The 1Password CLI package is `1password-cli`, which provides `op`. Bootstrap adds the official apt signing key, apt repository, debsig policy, and debsig keyring, then installs `1password-cli`.

Service-account verification uses commands compatible with service accounts:

```sh
. /root/.config/lab/op-token
op user get --me
op item list --vault "$LAB_OP_VAULT"
```

Commands using service-account auth source the relevant on-disk token file or pass `OP_SERVICE_ACCOUNT_TOKEN` through Ansible `environment:` with `no_log: true`; this repo prefers sourcing from the on-disk token file.

## Tailscale prerequisites

Create a reusable, pre-authorized, tagged auth key for `tag:lab`, store it in 1Password, and rotate it before expiry. Tailscale auth keys expire between 1 and 90 days; reusable keys still expire. Tagged devices normally have node-key expiry disabled by default, but the auth key is still needed for rebuilds and recovery if the machine must re-register.

Admin-side policy must allow tailnet network access to the tagged node. The box keeps OpenSSH running, but UFW denies public ingress and allows TCP/22 only on `tailscale0`.

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
      "ip": ["tcp:22"]
    }
  ]
}
```

Root login is intentionally not part of the normal path. Root-level debugging happens by connecting as the non-root user over Tailscale and using `sudo`. Break-glass is the provider console; a truly wedged box should be rebuilt.

Ephemeral nodes are usually removed shortly after going offline, commonly around 30-60 minutes. A re-registered node may get a different Tailscale IP, so outputs and runbooks steer you to the MagicDNS hostname, not a memorized IP.

When `allow_direct_udp: true`, the firewall allows inbound UDP 41641 for Tailscale direct connections. 41641 is the default Tailscale UDP port; if the implementation ever changes the tailscaled port with `--port`, the firewall rule must change accordingly.

## GitHub CLI and Git credentials

`gh auth login --with-token` is allowed. `gh auth setup-git` is forbidden because it writes Git credential-helper configuration that fights the chezmoi-owned `~/.gitconfig`.

After login, the workspace role runs `gh auth status` unmasked so README/logs show where `gh` says the credential is stored. `gh` may store credentials in an OS credential store when available. On a headless VPS without a usable credential store, expect plaintext fallback, commonly under `~/.config/gh/hosts.yml`; the role enforces `0600` if that file exists.

Security note: gh and agent credential stores are additional local credential stores that may contain cleartext tokens, depending on the CLI and credential-store availability.

Git HTTPS credentials come from the chezmoi-managed helper in `home/dot_gitconfig.tmpl`; Ansible does not write Git credential config. The helper emits both:

```text
username=x-access-token
password=<PAT read from 1Password>
```

The helper reads `OP_SERVICE_ACCOUNT_TOKEN` from the user token file and runs `op read "op://<lab-vault>/<github-pat-item>/<token-field>"`.

## OMP

OMP configuration lives in `home/dot_config/omp/`. `models.yml` is the provider config format expected by this repo, with a placeholder OpenAI Codex provider using:

```yaml
api: openai-codex-responses
apiKey: "!op read op://<lab-vault>/codex-subscription/subscription"
```

The mise role contains build-time assertions for the installed OMP from the box/user mise config. If an assertion fails, the role fails with the exact command output rather than silently substituting another agent architecture. Real API keys or Codex credentials are never committed.

## Workspace repositories

Public repo hygiene: committed work repo names/URLs are public. If private repo names are sensitive, move the work-repo list into a 1Password item and extend the workspace role to read it at runtime; this repo keeps the simple committed list only.

## Ubuntu 26.04 TODO

TODO: Re-evaluate migration to Ubuntu 26.04 LTS after the first 26.04.1 point release in August 2026 and after required vendor apt repositories publish `resolute` targets. Treat sudo-rs/uutils/Rust-userland changes as automation compatibility risks to test, not as a guaranteed full replacement of GNU userland tools.
