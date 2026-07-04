#!/usr/bin/env bash
set -euo pipefail

LAB_REPO_URL="${LAB_REPO_URL:?LAB_REPO_URL is required}"
LAB_REPO_REF="${LAB_REPO_REF:-main}"
LAB_BOOTSTRAP_DIR="${LAB_BOOTSTRAP_DIR:-/opt/lab}"
LAB_OP_TOKEN_FILE="${LAB_OP_TOKEN_FILE:-/root/.config/lab/op-token}"

install -d -m 0700 /root/.config/lab
if [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
  umask 077
  printf 'export OP_SERVICE_ACCOUNT_TOKEN=%s\n' "${OP_SERVICE_ACCOUNT_TOKEN}" > "${LAB_OP_TOKEN_FILE}"
fi
umask 022
if [ ! -s "${LAB_OP_TOKEN_FILE}" ]; then
  echo "missing OP service-account token file: ${LAB_OP_TOKEN_FILE}" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl gnupg git python3 python3-apt ansible debsig-verify

install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://downloads.1password.com/linux/keys/1password.asc \
  | gpg --dearmor -o /etc/apt/keyrings/1password-archive-keyring.gpg
chmod 0644 /etc/apt/keyrings/1password-archive-keyring.gpg
printf 'deb [arch=%s signed-by=/etc/apt/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/%s stable main\n' "$(dpkg --print-architecture)" "$(dpkg --print-architecture)" \
  > /etc/apt/sources.list.d/1password.list

install -d -m 0755 /etc/debsig/policies/AC2D62742012EA22 /usr/share/debsig/keyrings/AC2D62742012EA22
curl -fsSL https://downloads.1password.com/linux/debian/debsig/1password.pol \
  -o /etc/debsig/policies/AC2D62742012EA22/1password.pol
curl -fsSL https://downloads.1password.com/linux/keys/1password.asc \
  | gpg --dearmor -o /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg
chmod 0644 /etc/debsig/policies/AC2D62742012EA22/1password.pol /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg

apt-get update
apt-get install -y 1password-cli

. "${LAB_OP_TOKEN_FILE}"
op user get --me
if [ -n "${LAB_OP_VAULT:-}" ]; then
  op item list --vault "${LAB_OP_VAULT}"
fi

if [ -d "${LAB_BOOTSTRAP_DIR}/.git" ]; then
  git -C "${LAB_BOOTSTRAP_DIR}" fetch --depth=1 origin "${LAB_REPO_REF}"
  git -C "${LAB_BOOTSTRAP_DIR}" checkout --force FETCH_HEAD
else
  rm -rf "${LAB_BOOTSTRAP_DIR}"
  git clone --depth=1 --branch "${LAB_REPO_REF}" "${LAB_REPO_URL}" "${LAB_BOOTSTRAP_DIR}"
fi

ansible-pull \
  --url "${LAB_REPO_URL}" \
  --checkout "${LAB_REPO_REF}" \
  --directory "${LAB_BOOTSTRAP_DIR}" \
  ansible/site.yml
