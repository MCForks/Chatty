#!/usr/bin/env bash
set -euo pipefail

: "${BOOTSTRAP_SHA:?BOOTSTRAP_SHA is required}"
: "${INITIAL_TAG:?INITIAL_TAG is required}"

latest_tag="$(
  git tag --contains "$BOOTSTRAP_SHA" --list 'v[0-9]*' --sort=-v:refname \
    | head -n 1
)"
if [[ -z "$latest_tag" ]]; then
  latest_tag="$INITIAL_TAG"
fi

base_version="${latest_tag#v}"
if [[ ! "$base_version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "::error::Unsupported version tag: $latest_tag"
  exit 1
fi

major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"

if [[ "$latest_tag" == "$INITIAL_TAG" ]]; then
  range="${BOOTSTRAP_SHA}..HEAD"
  compare_base="$BOOTSTRAP_SHA"
else
  range="${latest_tag}..HEAD"
  compare_base="$latest_tag"
fi

commit_count="$(git rev-list --count "$range")"
if [[ "$commit_count" == "0" ]]; then
  echo "publish=false" >> "$GITHUB_OUTPUT"
  echo "No commits since $compare_base; skipping release."
  exit 0
fi

messages="$(git log --format='%s%n%b' "$range")"
if grep -Eq '^[a-z]+(\([^)]*\))?!:' <<<"$messages" \
    || grep -Eq '^BREAKING[ -]CHANGE:' <<<"$messages"; then
  major=$((major + 1))
  minor=0
  patch=0
elif grep -Eq '^feat(\([^)]*\))?:' <<<"$messages"; then
  minor=$((minor + 1))
  patch=0
elif grep -Eq '^(fix|perf)(\([^)]*\))?:' <<<"$messages"; then
  patch=$((patch + 1))
else
  echo "publish=false" >> "$GITHUB_OUTPUT"
  echo "No releasable Conventional Commits in $range; skipping release."
  exit 0
fi

version="${major}.${minor}.${patch}"
tag="v${version}"

write_section() {
  local title="$1"
  local pattern="$2"
  local entries
  entries="$(git log --reverse --format='- %s (%h)' "$range" \
    | grep -E -- "^- ${pattern}" || true)"
  if [[ -n "$entries" ]]; then
    printf '## %s\n\n%s\n\n' "$title" "$entries"
  fi
}

{
  printf '# Chatty %s\n\n' "$version"
  write_section "Breaking Changes" '[a-z]+(\([^)]*\))?!:'
  write_section "Features" 'feat(\([^)]*\))?:'
  write_section "Bug Fixes" 'fix(\([^)]*\))?:'
  write_section "Performance" 'perf(\([^)]*\))?:'
  write_section "Refactoring" 'refactor(\([^)]*\))?!?:'
  write_section "Build System" 'build(\([^)]*\))?!?:'
  write_section "CI/CD" 'ci(\([^)]*\))?:'
  write_section "Documentation" 'docs(\([^)]*\))?:'
  write_section "Tests" 'test(\([^)]*\))?:'
  write_section "Maintenance" 'chore(\([^)]*\))?:'
  printf '**Full Changelog:** https://github.com/%s/compare/%s...%s\n' \
    "$GITHUB_REPOSITORY" "$compare_base" "$tag"
} > release-notes.md

{
  echo "publish=true"
  echo "version=$version"
  echo "tag=$tag"
  echo "range=$range"
} >> "$GITHUB_OUTPUT"

echo "Prepared $tag from $commit_count commits in $range."
