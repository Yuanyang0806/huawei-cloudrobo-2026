#!/usr/bin/env bash
set -euo pipefail

ROOT="$HOME/workplace/projects/huawei-cloudrobo-2026"
PY="$HOME/workplace/software/miniforge3/envs/lerobot061/bin/python"

echo "===== Configure D405 ====="

"$PY" "$ROOT/scripts/configure_d405_ae.py"

echo
echo "===== Start A1Z REAL control ====="

cd "$ROOT/packages/r2c_sdk_python"

exec "$PY" -m r2c_sdk.cloudroboclient \
  --bundle "$ROOT/secrets/cert_config_Robot-dd9a_20260911105443.zip" \
  --robot-config "$ROOT/configs/runtime/a1z_real.yaml" \
  --log-level DEBUG
