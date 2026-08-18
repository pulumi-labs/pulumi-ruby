#!/usr/bin/env bash
#
# Syncs Pulumi's protobuf definitions from pulumi/pulumi and regenerates the Ruby
# bindings. The .proto sources are transient (gitignored); the generated Ruby under
# sdk/ruby/lib/pulumi/runtime/proto is checked in so that consumers of the gem never need
# protoc.
#
# Usage: scripts/sync-protos.sh [pulumi/pulumi git ref]

set -o errexit
set -o pipefail
set -o nounset

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROTO_REF="${1:-$(cat "$REPO_ROOT/proto/PULUMI_REF")}"
PROTO_DIR="$REPO_ROOT/proto"
OUT_DIR="$REPO_ROOT/sdk/ruby/lib/pulumi/runtime/proto"

# Prefer a sibling pulumi/pulumi checkout when one exists -- it makes local iteration
# on protocol changes possible without pushing a tag first.
SIBLING="$REPO_ROOT/../pulumi"

echo "==> Fetching protos (ref: $PROTO_REF)"
rm -rf "$PROTO_DIR/pulumi" "$PROTO_DIR/google"
if [ -d "$SIBLING/proto/pulumi" ] && [ "${USE_SIBLING:-}" = "1" ]; then
  echo "    using sibling checkout at $SIBLING"
  cp -R "$SIBLING/proto/pulumi" "$PROTO_DIR/pulumi"
  cp -R "$SIBLING/proto/google" "$PROTO_DIR/google"
else
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  git clone --quiet --depth 1 --branch "$PROTO_REF" \
    https://github.com/pulumi/pulumi.git "$TMP/pulumi"
  cp -R "$TMP/pulumi/proto/pulumi" "$PROTO_DIR/pulumi"
  cp -R "$TMP/pulumi/proto/google" "$PROTO_DIR/google"
fi

echo "==> Generating Ruby bindings"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

cd "$PROTO_DIR"
PROTO_FILES=$(find pulumi google -name '*.proto' | sort)

# shellcheck disable=SC2086
bundle exec --gemfile="$REPO_ROOT/sdk/ruby/Gemfile" grpc_tools_ruby_protoc \
  --proto_path=. \
  --ruby_out="$OUT_DIR" \
  --grpc_out="$OUT_DIR" \
  $PROTO_FILES

echo "==> Rewriting requires to be load-path independent"
ruby "$REPO_ROOT/scripts/relativize_requires.rb" "$OUT_DIR"

echo "==> Done. Generated $(find "$OUT_DIR" -name '*.rb' | wc -l | tr -d ' ') files."
