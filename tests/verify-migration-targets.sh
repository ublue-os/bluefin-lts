#!/usr/bin/env bash
# Verify that the live projectbluefin migration targets satisfy the existing key.
set -euo pipefail

POLICY_FILE="$(mktemp)"
readonly POLICY_FILE
trap 'rm -f "$POLICY_FILE"' EXIT

jq -n --arg key "${PWD}/cosign.pub" '{
  default: [{type: "reject"}],
  transports: {
    docker: {
      "ghcr.io/projectbluefin/bluefin-lts": [{
        type: "sigstoreSigned",
        keyPath: $key,
        signedIdentity: {type: "matchRepository"}
      }],
      "ghcr.io/projectbluefin/bluefin-lts-nvidia": [{
        type: "sigstoreSigned",
        keyPath: $key,
        signedIdentity: {type: "matchRepository"}
      }]
    }
  }
}' >"$POLICY_FILE"

skopeo inspect --policy "$POLICY_FILE" --override-arch amd64 \
  docker://ghcr.io/projectbluefin/bluefin-lts:stable >/dev/null
skopeo inspect --policy "$POLICY_FILE" --override-arch arm64 \
  docker://ghcr.io/projectbluefin/bluefin-lts:stable >/dev/null
skopeo inspect --policy "$POLICY_FILE" --override-arch amd64 \
  docker://ghcr.io/projectbluefin/bluefin-lts-nvidia:stable >/dev/null
