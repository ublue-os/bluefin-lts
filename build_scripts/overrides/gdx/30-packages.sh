#!/usr/bin/env bash

# FIXME: conda EPEL10 request: https://bugzilla.redhat.com/show_bug.cgi?id=2349089
dnf -y install \
  uv \
  nvtop
