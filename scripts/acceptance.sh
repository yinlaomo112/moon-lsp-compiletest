#!/usr/bin/env bash
set -euo pipefail

MOON_BIN="${MOON_BIN:-moon}"
MOON_LSP_BIN="${MOON_LSP_BIN:-moon-lsp}"
WARN_FLAGS=(--target native --warn-list +73 --deny-warn)
ALL_TARGET_FLAGS=(--target all --deny-warn)

"$MOON_BIN" fmt --check
"$MOON_BIN" check "${ALL_TARGET_FLAGS[@]}"
"$MOON_BIN" build "${ALL_TARGET_FLAGS[@]}"
"$MOON_BIN" test --target all --warn-list -68-1+73
"$MOON_BIN" check "${WARN_FLAGS[@]}"
"$MOON_BIN" build src/test/mock_lsp "${WARN_FLAGS[@]}"
"$MOON_BIN" build "${WARN_FLAGS[@]}"
"$MOON_BIN" test "${WARN_FLAGS[@]}"
"$MOON_BIN" fmt
"$MOON_BIN" fmt --check
"$MOON_BIN" info --target all

CLI="_build/native/debug/build/cmd/moon-lsp-compiletest/moon-lsp-compiletest.exe"
if [[ ! -x "$CLI" ]]; then
  echo "missing CLI binary: $CLI" >&2
  exit 2
fi

acceptance_tmp_dir="$(mktemp -d /tmp/moon-lsp-compiletest-acceptance.XXXXXX)"
trap 'rm -rf "$acceptance_tmp_dir"' EXIT

"$MOON_LSP_BIN" --version
"$CLI" --help
"$CLI" --server "$MOON_LSP_BIN" --timeout-ms 7000 --quiet-window-ms 100 --trace tests/cases

set +e
"$CLI" --server "$MOON_LSP_BIN" --timeout-ms 7000 \
  tests/failure-cases/message-mismatch
mismatch_status=$?
"$CLI" --server /bin/true tests/cases/unbound-to-fixed \
  >"$acceptance_tmp_dir/infrastructure.stdout" \
  2>"$acceptance_tmp_dir/infrastructure.stderr"
infrastructure_status=$?
set -e

if [[ "$mismatch_status" -ne 1 ]]; then
  echo "expected assertion exit 1, got $mismatch_status" >&2
  exit 2
fi
if [[ "$infrastructure_status" -ne 2 ]]; then
  echo "expected infrastructure exit 2, got $infrastructure_status" >&2
  exit 2
fi
if ! grep -q '^infrastructure failure:' "$acceptance_tmp_dir/infrastructure.stderr"; then
  echo "expected infrastructure evidence on stderr" >&2
  exit 2
fi
if ! grep -q '^ERROR ' "$acceptance_tmp_dir/infrastructure.stdout"; then
  echo "expected infrastructure summary on stdout" >&2
  exit 2
fi

echo "local acceptance passed"
