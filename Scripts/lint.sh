#!/usr/bin/env bash
# Lint changed Swift files. Full sweep: `Scripts/lint.sh $(git ls-files '*.swift')`.
#
# Default is report-only: the existing tree predates the formatter, so the
# first strict run reports layout debt. Set LINT_STRICT=1 in CI.
set -euo pipefail
cd "$(dirname "$0")/.."

files=()
if [ "$#" -gt 0 ]; then
  files=("$@")
else
  base="${LINT_BASE:-main}"
  while IFS= read -r file; do
    [ -f "$file" ] && files+=("$file")
  done < <(
    {
      git diff --name-only --diff-filter=ACMR "${base}..." -- '*.swift' || true
      git ls-files --others --exclude-standard -- '*.swift'
    } | sort -u
  )
fi

if [ "${#files[@]}" -eq 0 ]; then
  echo "lint: no changed Swift files"
  exit 0
fi

if [ "${LINT_STRICT:-0}" = "1" ]; then
  xcrun swift-format lint --strict "${files[@]}"
  if command -v swiftlint >/dev/null 2>&1; then
    swiftlint lint --strict --quiet -- "${files[@]}"
  else
    echo "lint: swiftlint 未安装，跳过（brew install swiftlint）" >&2
  fi
else
  xcrun swift-format lint "${files[@]}"
  if command -v swiftlint >/dev/null 2>&1; then
    swiftlint lint --quiet -- "${files[@]}"
  else
    echo "lint: swiftlint 未安装，跳过（brew install swiftlint）" >&2
  fi
fi
