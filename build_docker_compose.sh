#!/bin/bash
# Reproducible build entrypoint for container_template.
#
# Pins live in ./reproducible.env (single source of truth). SOURCE_DATE_EPOCH is
# derived from the git commit so the same commit always yields the same image
# bytes, on any machine. Verify bit-for-bit reproducibility with
# ../super/reproducible-build-verify.sh (or build twice with rewrite-timestamp and
# compare the containerimage.digest).

set -euo pipefail
cd "$(dirname "$0")"

# Load pins and export them so they are visible to bake/compose.
set -a
# shellcheck disable=SC1091
. ./reproducible.env
set +a

# Epoch 0 so rewrite-timestamp's clamp normalizes every file mtime.
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}"
echo "SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH}"

# Strip group/world write so COPY layer modes don't depend on the umask of
# whoever ran git checkout.
[ -d .git ] && find . -path ./.git -prune -o -exec chmod go-w {} +

# Shared args derived from reproducible.env, threaded into every bake target so the
# committed ARG defaults can be overridden centrally.
BAKE_SET=(
  --set "*.args.UBUNTU_REF=${UBUNTU_REF}"
  --set "*.args.ALPINE_REF=${ALPINE_REF}"
  --set "*.args.UBUNTU_SNAPSHOT=${UBUNTU_SNAPSHOT}"
  --set "*.args.SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH}"
)

FOUND_PREBUILT_IMAGE=false
for SERVICE in $(docker compose config --services); do
  IS_PREBUILT=$(docker inspect \
    --format '{{ index .Config.Labels "org.supernetworks.ci" }}' \
    "ghcr.io/spr-networks/super_${SERVICE}" \
    2>/dev/null || echo "false" \
  )
  if [ "$IS_PREBUILT" = "true" ]; then
    IMAGE="ghcr.io/spr-networks/super_${SERVICE}"
    echo "Removing prebuilt image ${IMAGE}"
    docker image rm -f "$IMAGE"
    FOUND_PREBUILT_IMAGE=true
  fi
done

if [ "$FOUND_PREBUILT_IMAGE" = "true" ]; then
    echo "Pruning dangling container images"
    docker image prune -f
fi

docker --help | grep buildx
missing_buildx=$?

if [ "$missing_buildx" -eq "1" ];
then
  export DOCKER_BUILDKIT=1
  export COMPOSE_DOCKER_CLI_BUILD=1
  docker compose build ${BUILDARGS:-} "$@"
else
  # We use docker buildx so we can build multi-platform images. Unfortunately,
  # a limitation is that multi-platform images cannot be loaded from the builder
  # into Docker. Pin the BuildKit backend image so the builder itself is
  # reproducible (rewrite-timestamp needs BuildKit >= 0.13).
  # Recreate super-builder if its BuildKit image doesn't match BUILDKIT_REF.
  if docker buildx inspect super-builder >/dev/null 2>&1; then
    CURRENT_BUILDKIT=$(docker buildx inspect super-builder \
      | sed -n 's/.*image="\([^"]*\)".*/\1/p' | head -1)
    if [ -n "${BUILDKIT_REF}" ] && [ "$CURRENT_BUILDKIT" != "${BUILDKIT_REF}" ]; then
      docker buildx rm super-builder
    fi
  fi
  docker buildx create --name super-builder --driver docker-container \
    --driver-opt "image=${BUILDKIT_REF}" \
    2>/dev/null || true

  # This script controls the exporter so that rewrite-timestamp=true is always
  # set: it rewrites in-layer file timestamps to SOURCE_DATE_EPOCH, which is what
  # actually makes the image bit-for-bit reproducible. SOURCE_DATE_EPOCH alone
  # only fixes the image "created" field, not the files inside the layers.
  #
  #   default  -> load the (single-arch) image into Docker  (type=docker)
  #   --push   -> push the (multi-arch) image to the registry (type=registry)
  # Multi-arch images cannot be loaded into Docker, so multi-arch always implies
  # --push. We translate --load/--push into the exporter rather than passing them
  # to bake directly (a bare --load would drop rewrite-timestamp).
  OUTPUT="type=docker,rewrite-timestamp=true"
  ARGS=()
  for a in "$@"; do
    case "$a" in
      --load) ;;                                              # default; ignore
      --push) OUTPUT="type=registry,rewrite-timestamp=true" ;;
      *) ARGS+=("$a") ;;
    esac
  done

  docker buildx bake \
    --builder super-builder \
    --file docker-compose.yml \
    "${BAKE_SET[@]}" --set "*.output=${OUTPUT}" ${BUILDARGS:-} "${ARGS[@]}"
fi

ret=$?

if [ "$ret" -ne "0" ]; then
  echo "Tip: if the build failed to resolve domain names,"
  echo "consider running ./base/docker_nftables_setup.sh"
  echo "since iptables has been disabled for docker in the"
  echo "SPR installer"
fi
