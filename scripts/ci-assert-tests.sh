#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <xcresult>" >&2
  exit 1
fi
if [[ ! -d "$1" ]]; then
  echo "error: xcresult bundle does not exist: $1" >&2
  exit 1
fi

summary_file=$(mktemp)
trap 'rm -f "$summary_file"' EXIT
xcrun xcresulttool get test-results summary --path "$1" --compact > "$summary_file"

python3 - "$summary_file" "$1" <<'PY'
import json
import os
import subprocess
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    summary = json.load(stream)
fields = ("totalTestCount", "passedTests", "failedTests", "skippedTests", "expectedFailures")
counts = {field: summary[field] for field in fields}
for field, value in counts.items():
    if type(value) is not int or value < 0:
        raise ValueError(f"Invalid {field}: {value!r}")
result = summary["result"]
allowed_skips = int(os.environ.get("ALLOWED_SKIPS", "0"))
min_tests = int(os.environ.get("MIN_TESTS", "1"))
if allowed_skips < 0 or min_tests < 0:
    raise ValueError("ALLOWED_SKIPS and MIN_TESTS must be nonnegative")

print("Test summary: " + ", ".join(
    [f"result={result}"] + [f"{field}={counts[field]}" for field in fields]
), flush=True)
summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
if summary_path:
    def cell(value):
        return str(value).replace("|", "\\|").replace("\n", " ").replace("\r", " ")

    with open(summary_path, "a", encoding="utf-8") as stream:
        stream.write("\n| Metric | Value |\n| --- | --- |\n")
        for field in ("result",) + fields:
            stream.write(f"| {field} | {cell(summary[field])} |\n")

failed = (
    counts["failedTests"] > 0
    or counts["skippedTests"] > allowed_skips
    or counts["totalTestCount"] < min_tests
)
if counts["skippedTests"]:
    try:
        output = subprocess.check_output([
            "xcrun", "xcresulttool", "get", "test-results", "tests",
            "--path", sys.argv[2], "--compact",
        ], text=True)
        tree = json.loads(output)

        def visit(node):
            if isinstance(node, list):
                for child in node:
                    visit(child)
            elif isinstance(node, dict):
                if node.get("result") == "Skipped":
                    name = node.get("nodeIdentifier") or node.get("name") or "<unnamed>"
                    print(f"Skipped: {name}")
                for key in ("testNodes", "children"):
                    visit(node.get(key))

        visit(tree)
    except Exception as error:
        print(f"Could not list skipped tests: {error}", file=sys.stderr)

if failed:
    print(
        f"error: Test assertions failed (allowed skips={allowed_skips}, minimum tests={min_tests})",
        file=sys.stderr,
    )
sys.exit(1 if failed else 0)
PY
