#!/usr/bin/env bash

set -xeuo pipefail

systemctl enable podman.socket
systemctl enable docker.socket
