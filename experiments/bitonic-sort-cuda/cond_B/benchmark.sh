#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
exec "$ROOT/run.sh" bitonic-sort-cuda "$HERE/planner/src" "$HERE/planner/out"
