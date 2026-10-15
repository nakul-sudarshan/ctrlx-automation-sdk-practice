#!/bin/sh
set -eu

for plug in datalayer active-solution; do
  until snapctl is-connected "$plug"; do
    echo "Waiting for plug $plug to be connected..."
    sleep 5
  done
done

until [ -d "$SNAP_COMMON/solutions/activeConfiguration" ]; do
  echo "Waiting for the active configuration directory"
  sleep 5
done

exec "$SNAP/datalayerClientSimple"