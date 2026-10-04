#!/usr/bin/env bash
# Release a new version: bump .toc version, tag, push, create GitHub release with LockoutTracker.zip.
# Usage: ./release.sh minor   1.5 -> 1.6 (first release: 0.1)
#        ./release.sh major   1.5 -> 2.0 (first release: 1.0)
set -euo pipefail

ADDON="LockoutTracker"
TOC="$ADDON.toc"

cd "$(dirname "$0")"

BUMP=${1:-}
if [ "$BUMP" != major ] && [ "$BUMP" != minor ]; then
    echo "Usage: $0 major|minor" >&2
    exit 1
fi

die() { echo "Error: $*" >&2; exit 1; }

command -v gh >/dev/null || die "gh (GitHub CLI) is not installed"
gh auth status >/dev/null 2>&1 || die "gh is not logged in (run: gh auth login)"

[ -z "$(git status --porcelain)" ] || die "working tree is not clean, commit or stash changes first"
[ "$(git branch --show-current)" = "main" ] || die "not on main branch"

echo "Fetching from remote..."
git fetch --prune --prune-tags --tags origin
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || die "main is not in sync with origin/main"

# Latest vX.Y tag
LAST=$(git tag -l 'v[0-9]*.[0-9]*' --sort=-v:refname | head -n 1)
if [ -z "$LAST" ]; then
    [ "$BUMP" = major ] && NEW="1.0" || NEW="0.1"
    echo "No tags yet, first release."
else
    MAJOR=${LAST#v}; MAJOR=${MAJOR%%.*}
    MINOR=${LAST##*.}
    if [ "$BUMP" = major ]; then NEW="$((MAJOR + 1)).0"; else NEW="$MAJOR.$((MINOR + 1))"; fi
    echo "Latest release: $LAST"
fi
TAG="v$NEW"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "tag $TAG already exists"

read -r -p "$TAG will be released. Press Enter to continue, Ctrl+C to abort. "

# Bump version in .toc (shown in the window title)
if ! grep -q "^## Version: $NEW\$" "$TOC"; then
    sed -i '' "s/^## Version: .*/## Version: $NEW/" "$TOC"
    git commit -q -m "Bump version to $NEW" -- "$TOC"
    git push -q origin main
    echo "Version in $TOC bumped to $NEW"
fi

git tag "$TAG"
git push -q origin "$TAG"
echo "Tag $TAG pushed"

# Zip addon files from the tagged commit: .toc, files it loads, Bindings.xml, LICENSE, README.md
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FILES=("$TOC")
while IFS= read -r line; do
    line=${line%$'\r'}
    [[ -z "$line" || "$line" == \#* ]] && continue
    FILES+=("$line")
done < "$TOC"
for f in Bindings.xml LICENSE README.md; do
    [ -f "$f" ] && FILES+=("$f")
done
git archive --format=zip --prefix="$ADDON/" -o "$TMP/$ADDON.zip" "$TAG" -- "${FILES[@]}"
echo "Packed: ${FILES[*]}"

gh release create "$TAG" "$TMP/$ADDON.zip" --title "$TAG" --generate-notes --verify-tag
