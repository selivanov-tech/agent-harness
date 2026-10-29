#!/usr/bin/env bash
# Runs every tests/*.test.sh with $TEST_BASH (default: bash from PATH).
# On macOS use TEST_BASH=/bin/bash to check bash 3.2 compatibility.
set -euo pipefail

cd "$(dirname "$0")"
bash_bin=${TEST_BASH:-bash}
failed=0
for test_file in ./*.test.sh; do
  printf '== %s\n' "${test_file#./}"
  if ! "$bash_bin" "$test_file"; then
    failed=1
  fi
done
exit "$failed"
