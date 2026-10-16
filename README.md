# ci

Shared GitHub Actions workflows for adriangalilea's packages: build, verify, and release notes in one place. Each repo keeps a short `release.yml` stub that calls these.

| Workflow | Does | Outputs |
|---|---|---|
| `python.yml` | `ruff check` + `ruff format --check` from the `dev` group, `uv build`, uploads `dist` | `tag`, `release` |
| `node.yml` | `pnpm install`, `pnpm run verify`, `pnpm run build`, `pnpm pack`, uploads `dist`; a package inside a repo with `directory`, `tag-prefix`, `bun` | `tag`, `release` |
| `swift.yml` | `swift build -c release`, `swift test` | |
| `mise.yml` | `mise run check`, then `git diff --exit-code` (the gate for repos whose verbs live in mise.toml) | |
| `release.yml` | git-cliff notes for `<previous semver tag>..HEAD`, then tag + GitHub release in one call, optional assets from an artifact; `tag-prefix` and `paths` for a package inside a repo | |
| `tap.yml` | bumps `Formula/<name>.rb` in [homebrew-tap](https://github.com/adriangalilea/homebrew-tap) to the tag's source tarball (needs a `TAP_TOKEN` secret: fine-grained, contents write on homebrew-tap only) | |

## Callers

Each caller's workflow points here; keep this table in step when one is added or moved.

| Repo | Workflows | Registry |
|---|---|---|
| [namecheap-python](https://github.com/adriangalilea/namecheap-python) | python, release | PyPI |
| [py-utils](https://github.com/adriangalilea/py-utils) | python, release | PyPI `adrian-utils` |
| [dkb](https://github.com/adriangalilea/dkb) | python, release | PyPI |
| [share](https://github.com/adriangalilea/share) | python, release | PyPI |
| [ts-utils](https://github.com/adriangalilea/ts-utils) | node, release | npm `@adriangalilea/utils` |
| [e-id](https://github.com/adriangalilea/e-id) | node, release (`cli/`, tags `cli-v…`) | npm `e-id` |
| [ip](https://github.com/adriangalilea/ip) | release, tap | Homebrew `adriangalilea/tap/ip` (source formula) |
| [swift-utils](https://github.com/adriangalilea/swift-utils) | swift, release, mise | git tags (SwiftPM) |
| [swift-hw](https://github.com/adriangalilea/swift-hw) | mise | git tags (SwiftPM, cut by hand) |
| [awake](https://github.com/adriangalilea/awake) | mise | cask, released by `ship` |
| [chill](https://github.com/adriangalilea/chill) | mise | cask, released by `ship` |

A CLI tool lives in the shared tap, never a `homebrew-<tool>` repo of its own: one `brew tap adriangalilea/tap` reaches all of them. Formulas build from the tagged source; a formula with a bottle (trash) is bumped by hand until bottles join `tap.yml`.

New Python packages get the stub from `pipinit` ([templates](https://github.com/adriangalilea/templates), `python/pyinit`).

## Not here: Mac app releases

A Mac app's release (sign, notarize, staple, dmg, Sparkle or cask) is `ship` in [swift-utils](https://github.com/adriangalilea/swift-utils), run locally where the Developer ID lives, with hand-written `notes/<version>.md` as the release body. These workflows generate notes with git-cliff and never sign anything. If app releases ever move to CI, the workflow belongs here as a thin caller of `ship`, not a second implementation.

## Why the publish job stays in each repo

PyPI and npm trusted publishing check the workflow file of the repo that publishes. A publish step inside a reusable workflow from another repo fails that check. So the stub owns the one job that holds `id-token: write`, and that job runs no project code: it downloads the artifact the read-only build job produced and uploads it.

## Idempotency

The GitHub release is the last step, and its absence is what triggers a run: `release` is true on a push to the default branch when `v<version>` has no release. Publishing skips a version the registry already has. A run that died after publishing is finished by the next push.

## Pinning

Callers pin to a full commit SHA with the version in a comment, and Dependabot (`github-actions` ecosystem) opens a PR when this repo tags a new version. Every action used here is pinned the same way.

Cut a version: `git tag v1.2.3 && git push --tags`.

## Stubs

### Python (PyPI)

Trusted publisher on PyPI: workflow `release.yml`, no environment. ruff must be in `[dependency-groups] dev`, not in an extra: lint installs only that group.

```yaml
name: release

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

permissions: {}

jobs:
  build:
    uses: adriangalilea/ci/.github/workflows/python.yml@<sha> # v1.0.0
    permissions:
      contents: read

  publish:
    needs: build
    if: needs.build.outputs.release == 'true'
    runs-on: ubuntu-latest
    permissions:
      id-token: write
    steps:
      - uses: actions/download-artifact@9000827ccba6bdab643e8b6fd33ac0654aef8333 # v8.0.2
        with:
          name: dist
          path: dist
      - uses: pypa/gh-action-pypi-publish@dc37677b2e1c63e2034f94d8a5b11f265b73ba33 # v1.14.2
        with:
          skip-existing: true

  release:
    needs: [build, publish]
    uses: adriangalilea/ci/.github/workflows/release.yml@<sha> # v1.0.0
    with:
      tag: ${{ needs.build.outputs.tag }}
    permissions:
      contents: write
```

### Node (npm)

Trusted publisher on npm: workflow `release.yml`, environment `npm`. package.json needs `packageManager` and a `verify` script.

```yaml
name: release

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

permissions: {}

jobs:
  build:
    uses: adriangalilea/ci/.github/workflows/node.yml@<sha> # v1.0.0
    permissions:
      contents: read

  publish:
    needs: build
    if: needs.build.outputs.release == 'true'
    runs-on: ubuntu-latest
    environment: npm
    permissions:
      id-token: write
    steps:
      - uses: actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1 # v7.1.0
        with:
          node-version: 24
      - uses: actions/download-artifact@9000827ccba6bdab643e8b6fd33ac0654aef8333 # v8.0.2
        with:
          name: dist
          path: dist
      - name: Publish
        run: |
          # ./ is load-bearing: npm reads `dist/x.tgz` as the GitHub repo dist/x.tgz.
          TGZ=$(echo ./dist/*.tgz)
          NAME=$(tar -xOzf "$TGZ" package/package.json | jq -r .name)
          VERSION=$(tar -xOzf "$TGZ" package/package.json | jq -r .version)
          if npm view "$NAME@$VERSION" version > /dev/null 2>&1; then
            echo "$NAME@$VERSION already on npm"
          else
            npm publish "$TGZ" --access public
          fi

  release:
    needs: [build, publish]
    uses: adriangalilea/ci/.github/workflows/release.yml@<sha> # v1.0.0
    with:
      tag: ${{ needs.build.outputs.tag }}
    permissions:
      contents: write
```

### Node package inside a repo (npm)

A package that is not the repo but lives in it (e-id's `cli/`), built against the repo's dependencies and types: the repo's root installs and runs `verify` as above, then the package is built and packed in `directory`. Its tags carry `tag-prefix` (`cli-v0.1.0`), so they are never the repo's own `v…`, and its notes list only the commits that touched `paths`. `bun: true` sets up Bun for a build script that runs it. The trusted publisher on npm names this file (`cli-release.yml`), not `release.yml`. Run it only when the package changed:

```yaml
name: cli-release

on:
  push:
    branches: [main]
    paths: ['cli/**']
  pull_request:
    branches: [main]
    paths: ['cli/**']

jobs:
  build:
    uses: adriangalilea/ci/.github/workflows/node.yml@<sha> # v1.3.0
    with:
      directory: cli
      tag-prefix: cli-
      bun: true
    permissions:
      contents: read

  publish: # the Node stub's, unchanged

  release:
    needs: [build, publish]
    uses: adriangalilea/ci/.github/workflows/release.yml@<sha> # v1.3.0
    with:
      tag: ${{ needs.build.outputs.tag }}
      tag-prefix: cli-
      paths: cli/**
    permissions:
      contents: write
```

### Swift library (tag-driven)

```yaml
name: release

on:
  push:
    tags: ['[0-9]+.[0-9]+.[0-9]+']

permissions: {}

jobs:
  verify:
    uses: adriangalilea/ci/.github/workflows/swift.yml@<sha> # v1.0.0
    permissions:
      contents: read

  release:
    needs: verify
    uses: adriangalilea/ci/.github/workflows/release.yml@<sha> # v1.0.0
    with:
      tag: ${{ github.ref_name }}
    permissions:
      contents: write
```

### Every caller

`.github/dependabot.yml`, so the `<sha>` pins move with this repo:

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
    groups:
      actions:
        patterns: ['*']
```
