#!/bin/bash
# Read the current checkout and print its next release tag. Empty output means no release.
set -euo pipefail
V=${1-}
case "$V" in v|'') ;; *) echo "expected v or an empty tag prefix" >&2; exit 64 ;; esac
if [ "$(git rev-parse --is-shallow-repository)" = true ]; then echo "release version requires full history" >&2; exit 1; fi
PATTERN="^${V}[0-9]+\.[0-9]+\.[0-9]+$"
LAST=$(git tag --merged HEAD --sort=-v:refname | { grep -E "$PATTERN" || true; } | sed -n 1p)
[ -n "$LAST" ] || { echo "no ${V}X.Y.Z tag yet: cut the first release by hand" >&2; exit 1; }
IFS=. read -r MAJOR MINOR PATCH <<< "${LAST#"$V"}"

BREAK=0; FEATURE=0; CHANGE=0
COMMITS=$(git rev-list --no-merges "$LAST..HEAD")
NOTES=$(git notes --ref=conventional list)
for commit in $COMMITS; do
  SUBJECT=$(git show -s --format=%s "$commit")
  BODY=$(git show -s --format=%b "$commit")
  if [[ "$NOTES"$'\n' == *" $commit"$'\n'* ]]; then
    SUBJECT=$(git notes --ref=conventional show "$commit")
    [[ -n "$SUBJECT" && "$SUBJECT" != *$'\n'* && "$SUBJECT" != *$'\r'* ]] || { echo "expected one correction title on $commit" >&2; exit 1; }
  fi
  # Two subjects carry no type and are still read: a repository's
  # first commit, `genesis` by the studio's convention, worth nothing,
  # and git's own revert subject, `Revert "…"`, a revert. A history
  # brought in whole (a subtree) holds both.
  [ "$SUBJECT" != genesis ] || continue
  if [[ "$SUBJECT" == 'Revert "'* ]]; then CHANGE=1; continue; fi
  TYPE_RE='^([a-z]+)(\([^)]*\))?(!)?: '
  [[ "$SUBJECT" =~ $TYPE_RE ]] || { echo "not a conventional commit, the bump cannot be read from it: $SUBJECT" >&2; exit 1; }
  TYPE="${BASH_REMATCH[1]}"
  if [ -n "${BASH_REMATCH[3]}" ] || grep -q '^BREAKING[ -]CHANGE:' <<< "$BODY"; then BREAK=1; fi
  case "$TYPE" in
    feat) FEATURE=1 ;;
    fix|perf|refactor|revert) CHANGE=1 ;;
    docs|style|test|ci|chore|build) ;;
    *) echo "unknown commit type '$TYPE': $SUBJECT" >&2; exit 1 ;;
  esac
# A merge carries no change of its own: its bump is read from the
# commits it brought in, each of which is conventional.
done

if [ "$MAJOR" = 0 ]; then
  if [ $BREAK = 1 ]; then NEXT="0.$((MINOR + 1)).0"
  elif [ $FEATURE = 1 ] || [ $CHANGE = 1 ]; then NEXT="0.$MINOR.$((PATCH + 1))"
  else NEXT=""; fi
else
  if [ $BREAK = 1 ]; then NEXT="$((MAJOR + 1)).0.0"
  elif [ $FEATURE = 1 ]; then NEXT="$MAJOR.$((MINOR + 1)).0"
  elif [ $CHANGE = 1 ]; then NEXT="$MAJOR.$MINOR.$((PATCH + 1))"
  else NEXT=""; fi
fi

printf '%s' "${NEXT:+$V$NEXT}"
