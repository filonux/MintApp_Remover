#!/usr/bin/env bash
# Static analysis with ShellCheck, at the version the CI pins (and checks by
# SHA-256, see .github/workflows/quality.yml). Every severity counts: the
# program and the suites must have no finding at all.
#   SHELLCHECK_BIN=path   use that ShellCheck (the CI sets it)
set -euo pipefail

PINNED_VERSION="0.11.0"
cd "$(dirname "${BASH_SOURCE[0]}")/.."

checker="${SHELLCHECK_BIN:-shellcheck}"
if ! command -v "$checker" >/dev/null 2>&1; then
    echo "lint.sh: ShellCheck $PINNED_VERSION is not installed (pip install shellcheck-py==$PINNED_VERSION.1)" >&2
    exit 1
fi
found="$("$checker" --version | sed -n 's/^version: //p')"
if [ "$found" != "$PINNED_VERSION" ]; then
    echo "lint.sh: warning: ShellCheck $found found, $PINNED_VERSION is the pinned version" >&2
    [ -z "${CI:-}" ] || exit 1
fi

files=(script/MintApp_Remover.sh tests/*.sh tests/lib/*.sh)
"$checker" -x -P SCRIPTDIR -s bash --severity=style "${files[@]}"
echo "ShellCheck $found: no findings in ${#files[@]} files"
