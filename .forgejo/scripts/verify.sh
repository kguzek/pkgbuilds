#!/usr/bin/env bash
# Checks every changed package: resets pkgrel after a pkgver bump, refreshes the checksums and
# .SRCINFO, then builds it. If anything had to change, the fixes are committed as actions-bot,
# signed, and pushed when PUSH_REF is set; the run fails either way, so the fixed commit is
# verified by a run of its own.
#
# Environment:
#   BASE_REF, BEFORE         see diff_base in common.sh
#   PUSH_REF                 branch to push fixes to; empty never pushes
#   ACTIONS_BOT_SIGNING_KEY  private SSH key that signs the fix commit (needed with PUSH_REF)
set -euo pipefail
# shellcheck source=common.sh
source "$(dirname "$0")/common.sh"

base=$(diff_base)
mapfile -t packages < <(changed_packages "$base")
if ((${#packages[@]} == 0)); then
  echo 'No packages changed.'
  exit 0
fi
echo "Checking: ${packages[*]}"

for dir in "${packages[@]}"; do
  echo "::group::$dir"

  # A new upstream version starts again at pkgrel 1; Renovate only changes pkgver.
  if [[ -n $base ]] && old=$(git show "$base:$dir/PKGBUILD" 2>/dev/null); then
    old_file=$(mktemp)
    printf '%s\n' "$old" >"$old_file"
    chmod 644 "$old_file"
    old_ver=$(pkgbuild_var "$old_file" pkgver)
    old_rel=$(pkgbuild_var "$old_file" pkgrel)
    rm -f "$old_file"
    new_ver=$(pkgbuild_var "$dir/PKGBUILD" pkgver)
    new_rel=$(pkgbuild_var "$dir/PKGBUILD" pkgrel)
    if [[ $new_ver != "$old_ver" && $new_rel == "$old_rel" && $new_rel != 1 ]]; then
      echo "pkgver $old_ver -> $new_ver: resetting pkgrel $new_rel -> 1"
      as_builder sed -i 's/^pkgrel=.*/pkgrel=1/' "$dir/PKGBUILD"
    fi
  fi

  (
    cd "$dir"
    as_builder updpkgsums
    as_builder makepkg --printsrcinfo >.SRCINFO
    as_builder makepkg --syncdeps --noconfirm --force --cleanbuild --noprogressbar
  )

  echo '::endgroup::'
done

paths=()
for dir in "${packages[@]}"; do
  paths+=("$dir/PKGBUILD" "$dir/.SRCINFO")
done
if [[ -z $(git status --porcelain -- "${paths[@]}") ]]; then
  echo 'All packages build, and their checksums and .SRCINFO are up to date.'
  exit 0
fi

git --no-pager diff -- "${paths[@]}"
mapfile -t fixed < <(git status --porcelain -- "${paths[@]}" | awk '{ print $2 }' | xargs -n1 dirname | sort -u)

if [[ -z ${PUSH_REF:-} || -z ${ACTIONS_BOT_SIGNING_KEY:-} ]]; then
  echo "::error::Out of date in ${fixed[*]}. Run updpkgsums and makepkg --printsrcinfo > .SRCINFO, and reset pkgrel to 1 after a pkgver bump."
  exit 1
fi

key=$(write_signing_key)
git add -- "${paths[@]}"
list=${fixed[*]}
git_as_bot "$key" commit --quiet -m "chore(${list// /, }): update checksums and .SRCINFO"
rm -f "$key"
git push --quiet origin "HEAD:refs/heads/$PUSH_REF"
echo "::error::Pushed fixes for ${fixed[*]} to $PUSH_REF; the new commit gets its own run."
exit 1
