#!/usr/bin/env bash
# Real checks: verify the archived image, start Nginx, and request its website.
set -euo pipefail

test -s dist/index.html
test -s dist/mission-control-image.tar.gz
test -s dist/Dockerfile
grep -Fq 'MISSION CONTROL' dist/index.html
sha256sum -c dist/SHA256SUMS

docker load -i dist/mission-control-image.tar.gz
container_id="$(docker run -d -p 127.0.0.1:18080:80 "mission-control:${GITHUB_SHA}")"
trap 'docker rm -f "$container_id" >/dev/null 2>&1 || true' EXIT

for attempt in $(seq 1 20); do
  if curl --fail --silent --show-error http://127.0.0.1:18080/ -o /tmp/mission-control-response.html 2>/dev/null; then
    break
  fi
  sleep 1
done

test -s /tmp/mission-control-response.html
cmp dist/index.html /tmp/mission-control-response.html
grep -Fq 'Initiate launch' /tmp/mission-control-response.html
printf '%s\n' 'PASS: image loads; Nginx serves the exact packaged Mission Control page.'
