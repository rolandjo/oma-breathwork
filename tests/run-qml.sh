#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
qa_dir=$(mktemp -d /tmp/breathwork-runtime.XXXXXX)
trap 'rm -rf -- "$qa_dir"' EXIT
ln -s /usr/share/omarchy/shell/Commons "$qa_dir/Commons"
ln -s /usr/share/omarchy/shell/Ui "$qa_dir/Ui"
ln -s "$repo_dir" "$qa_dir/plugin"
cp "$repo_dir/tests/runtime.qml" "$qa_dir/shell.qml"
timeout 15 quickshell -p "$qa_dir/shell.qml" --no-color 2>&1 | tee "$qa_dir/output.log"
grep -q 'PASS QML editor precision, date refresh, release, cues, and persistence' "$qa_dir/output.log"
if grep -Eq 'ERROR|TypeError|ReferenceError|FAIL' "$qa_dir/output.log"; then exit 1; fi
