#!/bin/sh

# Exit on error
set -e

VERSION=$(cat "$(dirname "$0")/version.txt")
if [ -n "$XDG_DATA_HOME" ]; then
  DATA_DIR="$XDG_DATA_HOME/nvim/refactorex"
else
  DATA_DIR="$HOME/.local/share/nvim/refactorex"
fi
ARCHIVE="refactorex-${VERSION}.tar.gz"
DOWNLOAD_URL="https://github.com/gp-pereira/refactorex/archive/refs/tags/${VERSION}.tar.gz"

mkdir -p "$DATA_DIR"

printf "Downloading RefactorEx %s...\n" "$VERSION"
curl -L --fail "$DOWNLOAD_URL" -o "$DATA_DIR/$ARCHIVE"

printf "Extracting archive...\n"
tar xzf "$DATA_DIR/$ARCHIVE" -C "$DATA_DIR"

rm "$DATA_DIR/$ARCHIVE"

cd "$DATA_DIR/refactorex-$VERSION/"
mix deps.get

printf "RefactorEx %s installed successfully to %s\n" "$VERSION" "$DATA_DIR"
