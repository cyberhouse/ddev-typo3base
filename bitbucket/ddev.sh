#!/bin/sh
#ddev-generated

# ddev commands in a Bitbucket pipeline step (image docker:*-cli, docker service), but without ddev itself:
# starts the ddev web image of ddev_version_constraint in .ddev/config.yaml and applies its php version,
# Node.js version and web_environment (see web-env.sh), so `ddev build` and the pipeline run the very same
# .ddev/commands/web/build
# Usage: .ddev/bitbucket/ddev.sh exec|composer|<web command>|<host command> [args...]
# Example: ".ddev/bitbucket/ddev.sh build be --prod", ".ddev/bitbucket/ddev.sh composer test:junit", ".ddev/bitbucket/ddev.sh exec typo3 list"

set -eu

[ -n "${BITBUCKET_BUILD_NUMBER:-}" ] || { echo "Only for bitbucket pipelines" >&2; exit 1; }

# host commands run in the step itself, with this script as their "ddev": it knows "ddev exec", which starts the web
# image as "web" in the network of the project like ddev - no other ddev command, and no docker-compose.*.yaml
if [ -f ".ddev/commands/host/${1:-}" ] && [ -x ".ddev/commands/host/${1:-}" ]; then
    command=.ddev/commands/host/$1
    shift
    export DDEV_SITENAME=bitbucket DDEV_APPROOT="$PWD"
    docker network inspect "ddev-${DDEV_SITENAME}_default" > /dev/null 2>&1 \
        || docker network create "ddev-${DDEV_SITENAME}_default" > /dev/null
    bin=$(mktemp -d)
    ln -s "$PWD/.ddev/bitbucket/ddev.sh" "$bin/ddev"
    PATH="$bin:$PATH" exec "$command" "$@"
fi
network=
if [ -n "${DDEV_SITENAME:-}" ]; then
    network="--network ddev-${DDEV_SITENAME}_default --network-alias web"
fi

# minimum version of ddev_version_constraint, e.g. ">= 1.25.4" -> v1.25.4
version=v$(sed -n 's/^ddev_version_constraint: *"[^0-9]*\([0-9.]*\)".*/\1/p' .ddev/config.yaml)
[ "$version" != v ] || { echo "No version in ddev_version_constraint of .ddev/config.yaml, e.g. \">= 1.25.4\"" >&2; exit 1; }

# root of the container is an unprivileged user outside of it (user namespace remapping of the docker service),
# e.g. frontend/node_modules restored from the cache would not be writable
chmod -R a+rwX .

# bind mounts are only available inside the clone dir
# shellcheck disable=SC2086
exec docker run --rm $network -v "$PWD:$PWD" -w "$PWD" -e BITBUCKET_BUILD_NUMBER -e COMPOSER_AUTH \
    "ddev/ddev-webserver:$version" .ddev/bitbucket/web-env.sh "$@"
