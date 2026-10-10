#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
scratch="$root/.build/consumers"
logs="$root/.build/consumer-results"
mkdir -p "$logs"

swift run --package-path "$root/Examples/NativeApp" --scratch-path "$scratch" \
  --jobs 6 NativeApp --print-spec > "$logs/native-openapi.json"
python3 - "$logs/native-openapi.json" <<'PY'
import json, sys
with open(sys.argv[1]) as source:
    spec = json.load(source)
assert spec["openapi"] == "3.1.0"
assert "/api/v1/pets/{int0}" in spec["paths"]
assert "201" in spec["paths"]["/api/v1/pets"]["post"]["responses"]
print("PASS external native-macro consumer and emitted OpenAPI")
PY

for fixture in MissingRequestSchema MissingResponseSchema OpaqueResponse RawResponse MalformedAnnotation; do
  log="$logs/$fixture.log"
  if OPENAPI_FAILURE="$fixture" swift build \
    --package-path "$root/Fixtures/CompileFailures" --scratch-path "$scratch" \
    --jobs 6 > "$log" 2>&1; then
    echo "FAIL: $fixture unexpectedly compiled" >&2
    exit 1
  fi
  case "$fixture" in
    MissingRequestSchema|MissingResponseSchema) expected="Schemable" ;;
    OpaqueResponse|RawResponse) expected="JSONResponse" ;;
    MalformedAnnotation) expected="status" ;;
  esac
  if ! grep -q "error:.*$expected" "$log"; then
    echo "FAIL: $fixture failed for an unexpected reason; see $log" >&2
    exit 1
  fi
  echo "PASS expected compile failure: $fixture"
done
