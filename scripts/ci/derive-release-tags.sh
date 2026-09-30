#!/usr/bin/env sh
set -eu

if [ -z "${CI_COMMIT_TAG:-}" ]; then
  echo "CI_COMMIT_TAG is not set, cannot publish release" >&2
  exit 1
fi

VERSION="${CI_COMMIT_TAG#v}"
IFS='.' read -r MAJOR MINOR _ <<EOF
$VERSION
EOF
MINOR_TAG="${MAJOR}"
if [ -n "${MINOR:-}" ]; then
  MINOR_TAG="${MAJOR}.${MINOR}"
fi

export VERSION MINOR_TAG MAJOR
