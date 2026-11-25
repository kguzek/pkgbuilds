# Shared helpers for the CI scripts. Sourced, not executed.
#
# The scripts run as root in an archlinux:base-devel container from the repository root;
# anything that evaluates a PKGBUILD runs as the unprivileged user "builder".

BOT_NAME='Actions Bot'
BOT_EMAIL='git+actions-bot@guzek.uk'

as_builder() {
  runuser -u builder -- env \
    SRCDEST=/tmp/makepkg/src PKGDEST=/tmp/makepkg/pkg BUILDDIR=/tmp/makepkg/build \
    "$@"
}

# Prints a variable from a PKGBUILD. Sourcing runs its top level, as makepkg does.
# shellcheck disable=SC2016 # expanded by the inner bash
pkgbuild_var() {
  as_builder bash -c 'source "$1" >/dev/null 2>&1; printf "%s" "${!2}"' _ "$1" "$2"
}

# Prints the commit to compare against: the merge base for a pull request, the previous tip for
# a push. Prints nothing when there is no usable base, meaning every package is checked.
#   BASE_REF  pull request target branch (empty for pushes)
#   BEFORE    commit before the push (empty for pull requests)
diff_base() {
  if [[ -n ${BASE_REF:-} ]]; then
    git fetch --quiet origin "refs/heads/$BASE_REF:refs/remotes/origin/$BASE_REF"
    git merge-base "origin/$BASE_REF" HEAD
  elif [[ -n ${BEFORE:-} && ! $BEFORE =~ ^0+$ ]] && git cat-file -e "$BEFORE^{commit}" 2>/dev/null; then
    printf '%s\n' "$BEFORE"
  fi
}

# Prints the package directories changed since $1, or all of them when $1 is empty or the CI
# itself changed.
changed_packages() {
  local base=$1 files all=false dir
  if [[ -z $base ]]; then
    all=true
  else
    files=$(git diff --name-only "$base" HEAD)
    if grep -qE '^(\.forgejo/|renovate\.json$)' <<<"$files"; then
      all=true
    fi
  fi
  if $all; then
    for dir in */; do
      dir=${dir%/}
      if [[ -f $dir/PKGBUILD ]]; then printf '%s\n' "$dir"; fi
    done
  else
    awk -F/ 'NF > 1 { print $1 }' <<<"$files" | sort -u | while read -r dir; do
      if [[ -f $dir/PKGBUILD ]]; then printf '%s\n' "$dir"; fi
    done
  fi
}

# Runs git with the bot as author and committer, signing with the SSH key in $1.
git_as_bot() {
  local key=$1
  shift
  git -c user.name="$BOT_NAME" -c user.email="$BOT_EMAIL" \
    -c gpg.format=ssh -c user.signingkey="$key" -c commit.gpgsign=true "$@"
}

# Writes the bot's signing key from ACTIONS_BOT_SIGNING_KEY to a private file and prints its path.
write_signing_key() {
  local key
  key=$(mktemp)
  printf '%s\n' "$ACTIONS_BOT_SIGNING_KEY" >"$key"
  printf '%s\n' "$key"
}
