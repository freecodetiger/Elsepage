#!/bin/sh
set -eu

# Deterministic EPUB packer for the RAG corpus.
#
#   usage: build-corpus-epub.sh <source-dir> <output-epub>
#
# Reproducibility is enforced rather than asserted: the archive is built twice
# into temp files and byte-compared before the destination is touched, so a
# non-deterministic pack (readdir order, clock, extra fields) fails the build
# instead of silently producing a corpus that cannot be regenerated.
#
# Prints "<sha256>  <output>" on success.

source_dir=${1:?usage: build-corpus-epub.sh <source-dir> <output-epub>}
output=${2:?usage: build-corpus-epub.sh <source-dir> <output-epub>}

[ -d "$source_dir" ] || { echo "no such source dir: $source_dir" >&2; exit 1; }
[ -f "$source_dir/mimetype" ] || { echo "missing $source_dir/mimetype" >&2; exit 1; }

# zip records mtime, so every member gets a fixed one. Without this the archive
# changes on every checkout even though the content did not.
find "$source_dir" -type f -exec touch -t 200001010000 {} +

# Explicit member order. `zip -r` walks readdir order, which APFS does not
# promise to keep stable; a locale-independent sort does.
members=$(cd "$source_dir" && find . -type f ! -name mimetype | sed 's|^\./||' | LC_ALL=C sort)

build() {
  dest=$1
  rm -f "$dest"
  (
    cd "$source_dir"
    # OCF requires mimetype first and stored (not deflated).
    zip -X0q "$dest" mimetype
    # shellcheck disable=SC2086
    zip -X9qD "$dest" $members
  )
  unzip -tq "$dest" >/dev/null
}

first=$(mktemp "${TMPDIR:-/tmp}/ragcorpus-a.XXXXXX")
second=$(mktemp "${TMPDIR:-/tmp}/ragcorpus-b.XXXXXX")
trap 'rm -f "$first" "$second"' EXIT INT TERM

build "$first"
build "$second"

a=$(shasum -a 256 <"$first" | cut -d' ' -f1)
b=$(shasum -a 256 <"$second" | cut -d' ' -f1)
[ "$a" = "$b" ] || { echo "non-reproducible archive for $source_dir ($a vs $b)" >&2; exit 1; }

mkdir -p "$(dirname -- "$output")"
mv "$first" "$output"
echo "$a  $output"
