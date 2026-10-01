# ddev-typo3base

DDEV add-on with the shared commands of Cyberhouse TYPO3 projects based on [typo3base](https://bitbucket.org/cyberhouse/typo3base).

| File | Purpose |
|---|---|
| `commands/web/build` | `ddev build [be\|fe] [--prod]` - composer + frontend build, the pipeline runs the same command |
| `commands/host/init` | initial setup (build, datasets, database import into an empty database, TYPO3 bootstrap, admin user) |
| `commands/host/ssh-remote` | `ddev ssh-remote [environment]` / `ddev bash-ssh` - bash console on a server of `.mage.yml` |
| `bitbucket/setup.sh` | prepares and starts DDEV as build container in a Bitbucket pipeline step |

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
| `BUILD_FRONTEND` | build | `frontend` (package.json scripts `build` and `ci`, empty: no frontend build) |
| `DATASET_DATABASE_URL`, `DATASET_FILES_URL` | init | dataset urls on the NAS |
| `BACKEND_ADMIN_USERNAME`, `BACKEND_ADMIN_PASSWORD` | init | backend admin, created if missing |

The initial setup runs automatically on the first `ddev start` with this hook in `.ddev/config.yaml`:

```yaml
hooks:
  post-start:
    - exec-host: '[ -f var/transient/ENABLE_INSTALL_TOOL ] || ddev init'
```

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
