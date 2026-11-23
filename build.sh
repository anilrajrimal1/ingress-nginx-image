#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
source versions.env

REGISTRY="${REGISTRY:-ghcr.io/anilrajrimal1/ingress-nginx}"
BASE="$REGISTRY/nginx:$NGINX_BASE_TAG"
CONTROLLER="$REGISTRY/controller:$CONTROLLER_TAG"
TRIVY="${TRIVY:-trivy}"
ALPINE=alpine:3.23.3@sha256:25109184c71bdad752c8312a8623239686a9a2071e8825f20acb8f2198c3f659

SRC=work/ingress-nginx
OUT=work/out
mkdir -p "$OUT"

die() { echo "error: $*" >&2; exit 1; }

fetch() {
  [[ -d $SRC ]] || git -c advice.detachedHead=false clone -q --depth 1 --branch "$FORK_REF" "$FORK_REPO" "$SRC"
  [[ $(git -C "$SRC" rev-parse HEAD) == "$FORK_COMMIT" ]] || die "$FORK_REF does not point to $FORK_COMMIT"
  [[ $(cat "$SRC/images/nginx/TAG") == "$NGINX_BASE_TAG" ]] || die "nginx base tag mismatch"
  [[ $(ls "$SRC/images/nginx/rootfs/patches" | wc -l) == "$NGINX_PATCHES" ]] || die "nginx patch count mismatch"
}

base() {
  docker buildx build --builder default --platform linux/amd64 --load --no-cache --progress plain \
    -t "$BASE" "$SRC/images/nginx/rootfs" 2>&1 | tee "$OUT/base.log"
  grep -oE ' Patch: [^ ]+' "$OUT/base.log" | awk '{print $2}' | sort > "$OUT/patches.txt" || true
  diff -q <(ls "$SRC/images/nginx/rootfs/patches" | sort) "$OUT/patches.txt" >/dev/null || die "not all patches applied"
  ! grep -qE 'FAILED|\.rej|Reversed' "$OUT/base.log" || die "a patch failed to apply"
}

case "${1:-build}" in
  build) fetch; base ;;
  *) die "usage: $0 [build]" ;;
esac
