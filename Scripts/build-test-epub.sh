#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_dir="$repo_root/Fixtures/MinimalEPUB"
output_dir="$repo_root/Tests/ReadLoopCoreTests/Fixtures/EPUB"
output="$output_dir/minimal.epub"

mkdir -p "$output_dir"
find "$source_dir" -type f -exec touch -t 200001010000 {} +
rm -f "$output"
(
  cd "$source_dir"
  zip -X0 "$output" mimetype >/dev/null
  zip -Xr9D "$output" META-INF EPUB >/dev/null
)
unzip -t "$output" >/dev/null
