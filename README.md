# ddev-typo3base

DDEV add-on with the shared commands of Cyberhouse TYPO3 projects based on [typo3base](https://bitbucket.org/cyberhouse/typo3base).

| File | Purpose |
|---|---|
| `commands/web/build` | `ddev build [be\|fe] [--prod] [--frontend=<dir>] [--backend=<dir>]` - composer + frontend build, the pipeline runs the same command |
| `commands/web/serve` | `ddev serve [--frontend=<dir>]` - frontend dev server (package.json script `serve`, must listen on all interfaces, e.g. `vite --host`), runs `build fe --serve` |
| `commands/host/init` | initial setup (build, datasets, database import into an empty database, TYPO3 bootstrap, admin user) |
| `commands/host/ssh-remote` | `ddev ssh-remote [environment]` / `ddev bash-ssh` - bash console on a server of `.mage.yml`, without environment a menu filtered by typing |
| `commands/host/scp-remote` | `ddev scp-remote <source>... <target>` - scp from, to and between servers of `.mage.yml`, remote as `<environment>:<path>` (e.g. `prod:~/typo3.sql.gz`, relative paths like `prod:composer.json` in `<host_path>/current`), copies between two servers go through the local host |
| `bitbucket/ddev.sh` | `ddev.sh build\|composer\|exec\|<host command> ...` - ddev commands in a Bitbucket pipeline step, see [Bitbucket pipeline](#bitbucket-pipeline) |
| `bitbucket/web-env.sh` | used by `bitbucket/ddev.sh`: php version, Node.js version, `web_environment` and `webimage_extra_packages` of `.ddev/config.yaml` in the web image (php versions not in the image, e.g. < 8.2 in ddev 1.25, are installed like ddev does, ~30s) |

## Installation / update

```
ddev add-on get cyberhouse/ddev-typo3base --version vX.Y.Z
```

The files are copied to `.ddev/` and committed with the project, so every project is pinned to a version.
An update is the same command with a newer version.

## Configuration (`web_environment` in `.ddev/config.yaml`)

| Variable | Used by | Example |
|---|---|---|
| `BUILD_LINKS` | build | `config/.htaccess frontend/build/{assets,css,js,snippets}` (linked into `public/`), `frontend/build:frontend` (as `public/frontend`, subdirectories allowed; braces around the whole pair: `frontend/build/{css:assets/css,js:assets/js}`) |
| `BUILD_FRONTEND` | build, serve | `frontend` (package.json scripts `build`, `ci` and `serve`, empty: no frontend build - `build fe` and `serve` fail, `--frontend=<dir>` builds another one) |
| `DATASET_DATABASE_URL`, `DATASET_FILES_URL` | init | dataset urls on the NAS |
| `BACKEND_ADMIN_USERNAME`, `BACKEND_ADMIN_PASSWORD` | init | backend admin, created if missing |

The initial setup runs automatically on the first `ddev start` with this hook in `.ddev/config.yaml`:

```yaml
hooks:
  post-start:
    - exec-host: '[ -f var/transient/ENABLE_INSTALL_TOOL ] || ddev init'
```

`ddev serve` is reachable at `https://<project url>:3000` with the dev server port exposed in `.ddev/config.yaml`:

```yaml
web_extra_exposed_ports:
  - name: Frontend
    container_port: 3000
    https_port: 3000
    http_port: 2999
```

The package manager of the frontend is chosen by its lock file: `package-lock.json` npm, `pnpm-lock.yaml` pnpm (not
part of the image, run by `npx` in the version of `packageManager` in `package.json`; its store is created as
`.pnpm-store` in the project root, add it to `.gitignore`), otherwise yarn. Several frontends
are built one at a time with `--frontend=<dir>`, e.g. one per pipeline step with
`.ddev/bitbucket/ddev.sh build fe --prod --frontend=$APP`. A frontend with a version file (`.nvmrc`, `.node-version`,
`.n-node-version`) runs with that Node.js version (`n exec`, downloads cached in the global ddev cache), otherwise with the
one of `nodejs_version`/`nodejs_root`. `ddev serve` installs the dependencies first, like the build (npm: `npm install`,
`npm ci` only for `--prod`).

The frontend build also runs without ddev, e.g. in a node image as step image when the build needs more memory than
the docker service of `ddev.sh` has (3 GB for 1x steps): `.ddev/commands/web/build fe --prod --frontend=$APP` - without
`n` in the image it is run by `npx`, so the version file of the frontend applies there too.

Another composer project (e.g. a second backend) is built with `--backend=<dir>`, e.g.
`.ddev/bitbucket/ddev.sh build be --prod --backend=api`: composer in that directory with the php version of the
project, `BUILD_LINKS` only belong to the project root.

## Bitbucket pipeline

`bitbucket/ddev.sh` runs the ddev commands of a pipeline step without ddev itself: it starts the ddev web image of
`ddev_version_constraint` in `.ddev/config.yaml` in the docker service, so local development and pipeline use the same
image and the very same `build` command. The repository variable `COMPOSER_AUTH` is required for private packages.

| ddev | Pipeline |
|---|---|
| `ddev build fe --prod` | `.ddev/bitbucket/ddev.sh build fe --prod` (Node.js of `nodejs_version`/`nodejs_root` is installed for `fe` and all targets) |
| `ddev composer test` | `.ddev/bitbucket/ddev.sh composer test` |
| `ddev exec typo3 list` | `.ddev/bitbucket/ddev.sh exec typo3 list` |
| `ddev qa unit` (host command, e.g. of [ddev-quality](https://github.com/cyberhouse/ddev-quality)) | `.ddev/bitbucket/ddev.sh qa unit` |

```yaml
ddev: &DDEV
  image: docker:29-cli
  services: [ docker ]

steps:

  - step: &FRONTEND
      name: Build Frontend
      <<: *DDEV
      caches: [ node ]
      script: [ .ddev/bitbucket/ddev.sh build fe --prod ]
      artifacts: [ frontend/build/** ]

  - step: &TYPO3
      name: Build TYPO3
      <<: *DDEV
      caches: [ composer ]
      script: [ .ddev/bitbucket/ddev.sh build be --prod ]
      artifacts: [ public/**, vendor/** ]

definitions:

  caches:
    node: { key: { files: [ frontend/yarn.lock ] }, path: frontend/node_modules }
    composer: .ci-cache/composer

  services:
    docker: { memory: 3072 } # = max for 1x size (4g minus 1g for the build container)
```

Notes:

* The frontend build runs inside the docker service, it needs more than the default 1024 MB of the service.
* The frontend cache depends on the package manager: yarn keeps `node_modules` (cache `node` above), `npm ci`
  removes it, so npm projects cache the npm cache instead, which `ddev.sh` puts into the clone dir - with several
  frontends e.g. `"frontend*/package-lock.json"` as key, steps with `caches: [ npm ]`:
  ```yaml
  npm: { key: { files: [ frontend/package-lock.json ] }, path: .ci-cache/npm }
  ```
* Host commands (`.ddev/commands/host`) run in the step itself, with `ddev.sh` as their `ddev`: it only knows
  `ddev exec`, which starts the web image as `web` in the network `ddev-${DDEV_SITENAME}_default` like ddev, so
  containers a host command starts in that network (e.g. a selenium) are reachable from it and the other way round.
  The step image has no bash, a host command for pipelines is a POSIX shell script (`#!/bin/sh`). The
  `docker-compose.*.yaml` of `.ddev/` are not applied.
* `ddev.sh` makes the clone dir writable for all: root of the container is an unprivileged user outside of it (user
  namespace remapping of the docker service), e.g. `node_modules` restored from the cache would not be writable.
* Starting the web image instead of ddev (`ddev start` with image build) or using it as step image (faster by ~15s, but
  the version would be in `bitbucket-pipelines.yml` too) were measured: ddev ~2m10s, step image ~1m, `ddev.sh` ~1m15s
  for composer install and tests. The docker cache was slower than pulling the image.
* `git` reports "dubious ownership" of the clone dir in the container, composer then can't detect the root package
  version - harmless as long as no package requires `self.version`.

## TYPO3 versions

`init` uses the TYPO3 core commands `extension:setup`, `backend:user:create` and `cache:flush`.
`install:fixfolderstructure` and `database:updateschema` of helhum/typo3-console run only if installed - they are needed
for datasets older than the code (`extension:setup` reads `be_users` before it updates the schema).
Changed commands of new TYPO3 versions are added in a new major version of this add-on, projects update it together with TYPO3.

| Add-on | Tested with |
|---|---|
| v1 | TYPO3 14, typo3-console 9 (optional) |

## Project specific changes

Remove the `#ddev-generated` line of a file to change it in a project: DDEV no longer overwrites it on updates.

## Contributing

This repository is public: it contains logic only, never values. Credentials, URLs, IP addresses and domains belong
in the `.ddev/config.yaml` of the project (`web_environment`).
