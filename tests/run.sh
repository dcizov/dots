#!/usr/bin/env bash
# Run the shell test suite: every tests/test_*.sh, or the files given.
#
#   bash tests/run.sh                          all of them
#   bash tests/run.sh tests/test_lib_common.sh one file
#
# Offline and unprivileged: every system command a script would run is a stub
# (see tests/harness.sh). The Python tests are separate:
#   python3 -B -m unittest discover -s tests
set -uo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

files=("$@")
((${#files[@]})) || files=("$here"/test_*.sh)

status=0
for f in "${files[@]}"; do
  bash "$f" || status=1
done
exit "$status"
