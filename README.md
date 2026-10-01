# ddev-typo3base

DDEV add-on with the shared commands of Cyberhouse TYPO3 projects based on [typo3base](https://bitbucket.org/cyberhouse/typo3base).

| File | Purpose |
|---|---|
| `commands/web/build` | `ddev build [be\|fe] [--prod]` - composer + frontend build, the pipeline runs the same command |
| `commands/web/serve` | `ddev serve` - frontend dev server (package.json script `serve`, must listen on all interfaces, e.g. `vite --host`) |
| `commands/host/init` | initial setup (build, datasets, database import into an empty database, TYPO3 bootstrap, admin user) |
| `commands/host/ssh-remote` | `ddev ssh-remote [environment]` / `ddev bash-ssh` - bash console on a server of `.mage.yml` |
| `bitbucket/ddev.sh` | `ddev.sh build\|composer\|exec ...` - ddev commands in a Bitbucket pipeline step, see [Bitbucket pipeline](#bitbucket-pipeline) |
| `bitbucket/web-env.sh` | used by `bitbucket/ddev.sh`: php version, Node.js version and `web_environment` of `.ddev/config.yaml` in the web image |

## Installation / update

```
ddev add-on get cyberhouse/ddev-typo3base --version vX.Y.Z
```

The files are copied to `.ddev/` and committed with the project, so every project is pinned to a version.
An update is the same command with a newer version.

## Configuration (`web_environment` in `.ddev/config.yaml`)

| Variable | Used by | Example |
|---|---|---|
| `BUILD_LINKS` | build | `config/.htaccess frontend/build/{assets,css,js,snippets}` (linked into `public/`) |
| `BUILD_FRONTEND` | build, serve | `frontend` (package.json scripts `build`, `ci` and `serve`, empty: no frontend build) |
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

## Bitbucket pipeline

`bitbucket/ddev.sh` runs the ddev commands of a pipeline step without ddev itself: it starts the ddev web image of
`ddev_version_constraint` in `.ddev/config.yaml` in the docker service, so local development and pipeline use the same
image and the very same `build` command. The repository variable `COMPOSER_AUTH` is required for private packages.

| ddev | Pipeline |
|---|---|
| `ddev build fe --prod` | `.ddev/bitbucket/ddev.sh build fe --prod` (Node.js of `nodejs_version`/`nodejs_root` is installed for `fe` and all targets) |
| `ddev composer test` | `.ddev/bitbucket/ddev.sh composer test` |
| `ddev exec typo3 list` | `.ddev/bitbucket/ddev.sh exec typo3 list` |

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
