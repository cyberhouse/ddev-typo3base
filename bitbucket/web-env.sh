#!/usr/bin/env bash
#ddev-generated

# Runs a ddev command inside the ddev web image started by .ddev/bitbucket/ddev.sh with php version,
# Node.js version and web_environment of .ddev/config.yaml applied, like ddev does in the web container
# Usage: .ddev/bitbucket/web-env.sh exec|composer|<web command> [args...]

set -euo pipefail

[ -n "${BITBUCKET_BUILD_NUMBER:-}" ] || { echo "Only for bitbucket pipelines" >&2; exit 1; }

config=.ddev/config.yaml

case "${1:-}" in
    exec)
        shift
        [ $# -gt 0 ] || { echo "Missing command for exec" >&2; exit 1; }
        ;;
    composer) ;;
    *)
        [ -f ".ddev/commands/web/${1:-}" ] && [ -x ".ddev/commands/web/${1:-}" ] || { echo "Unknown command '${1:-}'" >&2; exit 1; }
        set -- ".ddev/commands/web/$1" "${@:2}"
        ;;
esac

php_version=$(yq '.php_version' "$config")
# the image only contains the current php versions, older ones are installed like ddev does when it builds the image
# (~30s), xdebug and xhprof disabled like in the web container of ddev
if [ ! -x "/usr/bin/php$php_version" ]; then
    install_php_extensions.sh "php$php_version" "$(dpkg --print-architecture)" > /dev/null
    phpdismod -v "$php_version" xdebug xhprof
fi
update-alternatives --set php "/usr/bin/php$php_version" > /dev/null 2>&1 \
    || { echo "PHP $php_version (php_version of $config) is not available" >&2; exit 1; }
while IFS= read -r line; do export "$line"; done < <(yq '.web_environment[]' "$config")

# webimage_extra_packages are installed like ddev does when it builds the image (~10s), e.g. libraries of binaries
# that node packages download
packages=$(yq '.webimage_extra_packages // [] | join(" ")' "$config")
if [ -n "$packages" ]; then
    apt-get update -qq > /dev/null
    # shellcheck disable=SC2086
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends $packages > /dev/null
fi

# Node.js version of nodejs_version/nodejs_root only for the frontend build ("fe" or all targets), otherwise
# the default version of the image is kept (the download is not needed)
if [ "$1" = .ddev/commands/web/build ] && [[ " ${*:2} " != *" be "* ]]; then
    nodejs_version=$(yq '.nodejs_version // ""' "$config")
    if [ -n "$nodejs_version" ]; then
        # auto/engine read the version files (.nvmrc, package.json engines, ...) of nodejs_root like ddev
        (cd "$(yq '.nodejs_root // "."' "$config")" && N_PREFIX=/usr/local/n n install --cleanup "$nodejs_version" > /dev/null)
        hash -r
    fi
fi

# composer binaries without path like in the web container of ddev
export PATH="$PWD/vendor/bin:$PATH"

# composer cache inside the clone dir (bitbucket cache), auth by repository variable COMPOSER_AUTH
export COMPOSER_CACHE_DIR="$PWD/.ci-cache/composer"
# set git to trust repositories of all owners (safe.directory=*), so the composer cache can be reused in subsequent steps
git config --global --add safe.directory '*'
# npm cache inside the clone dir (bitbucket cache) - npm ci removes node_modules, so this is the cache to keep
export npm_config_cache="$PWD/.ci-cache/npm"

exec "$@"
