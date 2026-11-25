# pkgbuilds

Arch Linux packaging recipes, one directory per package.

- [`monocode-bin`](monocode-bin/) — stable MonoCode desktop release for x86_64.

## Updates

Renovate bumps `pkgver` for every PKGBUILD whose `pkgver` line carries a comment naming the
upstream source:

```bash
pkgver=0.16.0 # renovate: datasource=github-releases depName=hardbeat920/monocode
```

Only plain numeric versions count, with an optional leading `v` (`v0.17.0` becomes `0.17.0`);
tags such as `native-v0.16.0-preview.14` are ignored. A PKGBUILD without the comment is never
updated.

The CI workflow (`CI / check`) then resets `pkgrel`, refreshes the checksums and `.SRCINFO`, and
builds the package. When it has to change anything on a pull request, actions-bot commits the
fix (signed) and the new commit is checked again. Renovate merges once the check passes, and the CD
workflow (`CD / publish`) pushes every changed package to the AUR.

The same check runs on any other pull request, so a hand-edited PKGBUILD only needs its
`pkgver` changed.
