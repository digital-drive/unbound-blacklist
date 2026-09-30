#!/usr/bin/env sh
set -eu

if [ -z "${CI_COMMIT_TAG:-}" ]; then
  echo "CI_COMMIT_TAG is not set, cannot publish release" >&2
  exit 1
fi

VERSION="${CI_COMMIT_TAG#v}"
IFS='.' read -r MAJOR MINOR _ <<EOF_VERSION
$VERSION
EOF_VERSION
MINOR_TAG="${MAJOR}"
if [ -n "${MINOR:-}" ]; then
  MINOR_TAG="${MAJOR}.${MINOR}"
fi

# Pre-releases (e.g. 1.2.0-rc.1, 1.0.0-2) only get their exact version tag;
# moving tags (major, major.minor, latest) are reserved for stable releases.
case "$VERSION" in
  *-*|*+*)
    IS_PRERELEASE="true"
    ;;
  *)
    IS_PRERELEASE="false"
    ;;
esac

export VERSION MINOR_TAG MAJOR IS_PRERELEASE
