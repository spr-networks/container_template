#!/usr/bin/env bash
# update-pins.sh — re-resolve pins, rewrite reproducible.env, and sync the
# `ARG <KEY>=` defaults / `# syntax=` line in the Dockerfile. Read-only lookups
# (registry manifest inspect). Review with `git diff`.
# Tip: `docker login` first to avoid Docker Hub's unauthenticated pull-rate-limit (429).
set -euo pipefail
cd "$(dirname "$0")"

# ---- tracked refs (edit to bump, then re-run) ----
UBUNTU_TAG=ubuntu:24.04
ALPINE_TAG=alpine:latest
DOCKERFILE_TAG=docker/dockerfile:1
BUILDKIT_TAG=moby/buildkit:buildx-stable-1

mdigest() { docker buildx imagetools inspect "$1" --format '{{.Manifest.Digest}}'; }

echo "Resolving pins..." >&2
UBUNTU_REF="${UBUNTU_TAG}@$(mdigest "$UBUNTU_TAG")"
ALPINE_REF="${ALPINE_TAG%%:*}@$(mdigest "$ALPINE_TAG")"
DOCKERFILE_SYNTAX="${DOCKERFILE_TAG}@$(mdigest "$DOCKERFILE_TAG")"
BUILDKIT_REF="${BUILDKIT_TAG}@$(mdigest "$BUILDKIT_TAG")"
UBUNTU_SNAPSHOT="${UBUNTU_SNAPSHOT:-$(grep -E '^UBUNTU_SNAPSHOT=' reproducible.env | cut -d= -f2)}"
code=$(curl -fsS -o /dev/null -w '%{http_code}' "https://snapshot.ubuntu.com/ubuntu/${UBUNTU_SNAPSHOT}/dists/noble/InRelease" || true)
[ "$code" = "200" ] || { echo "snapshot ${UBUNTU_SNAPSHOT} not valid (HTTP $code)" >&2; exit 1; }

echo "Writing reproducible.env" >&2
cat > reproducible.env <<EOF
# Pinned build inputs for build_docker_compose.sh and CI. Regenerate with ./update-pins.sh.
UBUNTU_REF=${UBUNTU_REF}
ALPINE_REF=${ALPINE_REF}
DOCKERFILE_SYNTAX=${DOCKERFILE_SYNTAX}
BUILDKIT_REF=${BUILDKIT_REF}
UBUNTU_SNAPSHOT=${UBUNTU_SNAPSHOT}
EOF

echo "Syncing Dockerfile ARG defaults + # syntax= line" >&2
replace_line() {  # <file> <sed-pattern> <new-line>  (sed: no @/$ interpolation)
  local f="$1" pat="$2" new="$3" tmp; tmp=$(mktemp)
  sed "s|${pat}|${new}|" "$f" > "$tmp" && mv "$tmp" "$f"
}
while IFS='=' read -r k v; do
  case "$k" in ''|\#*) continue;; esac
  if [ "$k" = "DOCKERFILE_SYNTAX" ]; then
    replace_line Dockerfile '^# syntax=.*' "# syntax=${v}"
  else
    replace_line Dockerfile "^ARG ${k}=.*" "ARG ${k}=${v}"
  fi
done < reproducible.env

echo "Done. Review with: git diff" >&2
