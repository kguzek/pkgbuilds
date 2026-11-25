#!/usr/bin/env bash
# Pushes every changed package to its AUR repository, named after its pkgbase. Packages whose
# .SRCINFO doesn't match their PKGBUILD are refused. A package with nothing new is skipped, so
# rerunning is safe.
#
# Environment:
#   BEFORE                   see diff_base in common.sh
#   AUR_SSH_KEY              private SSH key registered on the AUR account
#   ACTIONS_BOT_SIGNING_KEY  private SSH key that signs the AUR commits
set -euo pipefail
# shellcheck source=common.sh
source "$(dirname "$0")/common.sh"

# Published at https://aur.archlinux.org (SHA256:RFzBCUItH9LZS0cKB5UE6ceAYhBD5C8GeOBip8Z11+4).
AUR_HOST_KEY='aur.archlinux.org ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEuBKrPzbawxA/k2g6NcyV5jmqwJ2s+zpgZGZ7tpLIcN'

base=$(diff_base)
mapfile -t packages < <(changed_packages "$base")
if ((${#packages[@]} == 0)); then
  echo 'No packages changed.'
  exit 0
fi

ssh_dir=$(mktemp -d)
printf '%s\n' "$AUR_SSH_KEY" >"$ssh_dir/aur"
chmod 600 "$ssh_dir/aur"
printf '%s\n' "$AUR_HOST_KEY" >"$ssh_dir/known_hosts"
export GIT_SSH_COMMAND="ssh -i $ssh_dir/aur -o IdentitiesOnly=yes -o UserKnownHostsFile=$ssh_dir/known_hosts -o StrictHostKeyChecking=yes"
key=$(write_signing_key)
trap 'rm -rf "$ssh_dir" "$key"' EXIT

message="$(git log -1 --format=%s)

Source: $GITHUB_SERVER_URL/$GITHUB_REPOSITORY/commit/$(git rev-parse HEAD)"

for dir in "${packages[@]}"; do
  echo "::group::$dir"

  if ! diff -u "$dir/.SRCINFO" <(cd "$dir" && as_builder makepkg --printsrcinfo); then
    echo "::error::$dir/.SRCINFO doesn't match its PKGBUILD"
    exit 1
  fi
  pkgbase=$(sed -n 's/^pkgbase = //p' "$dir/.SRCINFO")

  work=$(mktemp -d)
  git clone --quiet "ssh://aur@aur.archlinux.org/$pkgbase.git" "$work"
  git -C "$work" rm -rq --ignore-unmatch .
  git archive --format=tar "HEAD:$dir" | tar -x -C "$work"
  git -C "$work" add -A
  if git -C "$work" diff --cached --quiet; then
    echo "$pkgbase is already up to date on the AUR."
  else
    git -C "$work" --no-pager diff --cached --stat
    git_as_bot "$key" -C "$work" commit --quiet -m "$message"
    git -C "$work" push --quiet origin HEAD:master
    echo "Published $pkgbase."
  fi
  rm -rf "$work"

  echo '::endgroup::'
done
