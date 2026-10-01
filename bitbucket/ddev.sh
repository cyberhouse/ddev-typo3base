#!/bin/sh
#ddev-generated

# ddev commands in a Bitbucket pipeline step (image docker:*-cli, docker service), but without ddev itself:
# starts the ddev web image of ddev_version_constraint in .ddev/config.yaml and applies its php version,
# Node.js version and web_environment (see web-env.sh), so `ddev build` and the pipeline run the very same
# .ddev/commands/web/build
# Usage: .ddev/bitbucket/ddev.sh exec|composer|<web command> [args...]
# Example: ".ddev/bitbucket/ddev.sh build be --prod", ".ddev/bitbucket/ddev.sh composer test:junit", ".ddev/bitbucket/ddev.sh exec typo3 list"

set -eu

[ -n "${BITBUCKET_BUILD_NUMBER:-}" ] || { echo "Only for bitbucket pipelines" >&2; exit 1; }

# minimum version of ddev_version_constraint, e.g. ">= 1.25.4" -> v1.25.4
version=v$(sed -n 's/^ddev_version_constraint: *"[^0-9]*\([0-9.]*\)".*/\1/p' .ddev/config.yaml)
[ "$version" != v ] || { echo "No version in ddev_version_constraint of .ddev/config.yaml, e.g. \">= 1.25.4\"" >&2; exit 1; }

# root of the container is an unprivileged user outside of it (user namespace remapping of the docker service),
# e.g. frontend/node_modules restored from the cache would not be writable
chmod -R a+rwX .

# bind mounts are only available inside the clone dir
exec docker run --rm -v "$PWD:$PWD" -w "$PWD" -e BITBUCKET_BUILD_NUMBER -e COMPOSER_AUTH \
    "ddev/ddev-webserver:$version" .ddev/bitbucket/web-env.sh "$@"
