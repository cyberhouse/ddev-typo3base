#!/bin/sh
#ddev-generated
# Prepares and starts DDEV in a Bitbucket pipeline step (image docker:*-cli, runtime v3) as pure
# build container: only the web container is started - no database, router, ssh-agent or
# additional services (docker-compose.*.yaml). The project is not reachable in the pipeline.
# Afterwards the pipeline uses the very same `ddev ...` commands as local development.

set -eu

[ -n "${BITBUCKET_BUILD_NUMBER:-}" ] || { echo "Only for bitbucket pipelines - it modifies .ddev and the global ddev config" >&2; exit 1; }

# minimum version of ddev_version_constraint in .ddev/config.yaml, e.g. ">= 1.25.0" -> v1.25.0
DDEV_VERSION=v$(sed -n 's/^ddev_version_constraint: *"[^0-9]*\([0-9.]*\)".*/\1/p' .ddev/config.yaml)
DDEV_ARCH=$(uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')
CI_HOME="$BITBUCKET_CLONE_DIR/.ci-home"

apk add --no-cache bash curl sudo
curl -fsSL "https://github.com/ddev/ddev/releases/download/${DDEV_VERSION}/ddev_linux-${DDEV_ARCH}.${DDEV_VERSION}.tar.gz" \
    | tar -xz -C /usr/local/lib ddev

# ddev refuses to run as root, global ddev config must live inside the clone dir
# (bind mounts outside of it are not available to the docker service)
adduser -D -u 1000 ci
cat > /usr/local/bin/ddev <<EOF
#!/bin/sh
exec sudo -u ci -- env HOME="$CI_HOME" DOCKER_HOST="\${DOCKER_HOST:-}" DDEV_NONINTERACTIVE=true /usr/local/lib/ddev "\$@"
EOF
chmod +x /usr/local/bin/ddev

rm -f .ddev/docker-compose.*.yaml
printf "omit_containers: [db]\n" > .ddev/config.ci.yaml

# composer auth from repository variable, composer cache inside clone dir (bitbucket cache),
# appended to keep variables of the project
printf "\nCOMPOSER_AUTH='%s'\nCOMPOSER_CACHE_DIR=/var/www/html/.ci-home/composer\n" "${COMPOSER_AUTH:-\{\}}" >> .ddev/.env

# skip the initial setup hook of .ddev/config.yaml (no database and datasets in the pipeline)
mkdir -p var/transient && touch var/transient/ENABLE_INSTALL_TOOL

mkdir -p "$CI_HOME/composer"
chown -R ci "$BITBUCKET_CLONE_DIR"

ddev config global --omit-containers=ddev-router,ddev-ssh-agent --instrumentation-opt-in=false
ddev start
