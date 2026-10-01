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

update-alternatives --set php "/usr/bin/php$(yq '.php_version' "$config")" > /dev/null 2>&1
while IFS= read -r line; do export "$line"; done < <(yq '.web_environment[]' "$config")

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

exec "$@"
