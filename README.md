# ci

Shared GitHub Actions workflows for adriangalilea's packages: build, verify, and release notes in one place. Each repo keeps a short `release.yml` stub that calls these.

| Workflow | Does | Outputs |
|---|---|---|
| `python.yml` | `ruff check` + `ruff format --check` from the `dev` group, `uv build`, uploads `dist` | `tag`, `release` |
| `node.yml` | `pnpm install`, `pnpm run verify`, `pnpm run build`, `pnpm pack`, uploads `dist`; a package inside a repo with `directory`, `tag-prefix`, `bun`, its own gate with `verify`, and its own artifact name with `artifact` (several packages in one run) | `tag`, `release` |
| `swift.yml` | `swift build -c release`, `swift test` | |
| `mise.yml` | `mise run check` (or the `task` named, with its arguments), then `git diff --exit-code` (the gate for repos whose verbs live in mise.toml); called once per task, a slow gate runs as parallel jobs; `cache` keeps a build directory between runs, so a push recompiles only what it touched | |
| `next-version.yml` | the next version from the conventional commits since the last semver tag, so releasing is never a decision: in 0.x a break bumps the minor and anything else worth a release the patch (a consumer pinning `.upToNextMinor` never takes a break); from 1.0, semver; only docs/style/test/ci/chore/build is no release; a non-conventional commit stops the run; `v-prefix` off for SwiftPM's `1.2.3` | `tag` (empty: nothing to release) |
| `release.yml` | git-cliff notes for `<previous semver tag>..HEAD`, then tag + GitHub release in one call, optional assets from an artifact; `tag-prefix` and `paths` for a package inside a repo | |
| `actions/npm-publish` | the steps of a caller's npm publish job: downloads the tarball `node.yml` packed (`artifact`, default `dist`) and publishes it through trusted publishing; a version npm already has counts as published | |
| `tap.yml` | bumps `Formula/<name>.rb` in [homebrew-tap](https://github.com/adriangalilea/homebrew-tap) to the tag's source tarball (needs a `TAP_TOKEN` secret: fine-grained, contents write on homebrew-tap only) | |

## Callers

Each caller's workflow points here; keep this table in step when one is added or moved.

| Repo | Workflows | Registry |
|---|---|---|
| [namecheap-python](https://github.com/adriangalilea/namecheap-python) | python, release | PyPI |
| [py-utils](https://github.com/adriangalilea/py-utils) | python, release | PyPI `adrian-utils` |
| [dkb](https://github.com/adriangalilea/dkb) | python, release | PyPI |
| [share](https://github.com/adriangalilea/share) | python, release | PyPI |
| [ts-utils](https://github.com/adriangalilea/ts-utils) | node, release (one per package in `packages/`; tags `v…`, `llm-v…`, `bot-v…`, `metrics-v…`) | npm `@adriangalilea/utils`, `@adriangalilea/llm`, `@adriangalilea/bot`, `@adriangalilea/metrics` |
| [e-id](https://github.com/adriangalilea/e-id) | node, release (`cli/`, tags `cli-v…`) | npm `@e-id/eid` |
| [ip](https://github.com/adriangalilea/ip) | release, tap | Homebrew `adriangalilea/tap/ip` (source formula) |
| [swift-utils](https://github.com/adriangalilea/swift-utils) | mise, next-version, release (released by CI on every green push to main) | git tags (SwiftPM) |
| [swift-hw](https://github.com/adriangalilea/swift-hw) | mise | git tags (SwiftPM, cut by hand) |
| [awake](https://github.com/adriangalilea/awake) | mise | cask, released by `ship` |
| [chill](https://github.com/adriangalilea/chill) | mise | cask, released by `ship` |

A CLI tool lives in the shared tap, never a `homebrew-<tool>` repo of its own: one `brew tap adriangalilea/tap` reaches all of them. Formulas build from the tagged source; a formula with a bottle (trash) is bumped by hand until bottles join `tap.yml`.

New Python packages get the stub from `pipinit` ([templates](https://github.com/adriangalilea/templates), `python/pyinit`).

## Not here: Mac app releases

A Mac app's release (sign, notarize, staple, dmg, Sparkle or cask) is built locally from a fresh clone of commits a person approved, the keys handed to that build alone, then published by `ship` in [swift-utils](https://github.com/adriangalilea/swift-utils), with hand-written `notes/<version>.md` as the release body. These workflows generate notes with git-cliff and never sign anything. If app releases ever move to CI, the workflow belongs here as a thin caller of `ship`, not a second implementation.

## Why the publish job stays in each repo

PyPI and npm trusted publishing check the workflow file of the repo that publishes. A publish step inside a reusable workflow from another repo fails that check. So the stub owns the one job that holds `id-token: write`, and that job runs no project code: it downloads the artifact the read-only build job produced and uploads it. Its steps can still live here: `actions/npm-publish` is a composite action, which runs inside the caller's job, so the token npm checks still names the caller's file and environment.

## Idempotency

The GitHub release is the last step, and its absence is what triggers a run: `release` is true on a push to the default branch when `v<version>` has no release. Publishing skips a version the registry already has. A run that died after publishing is finished by the next push.

npm is asked by publishing, never by `npm view` first: for minutes after a version goes up, `npm view` can answer 404 for it while `npm publish` already refuses it, so a pre-check races the registry. `actions/npm-publish` reads that refusal ("cannot publish over the previously published versions") as published. A staged version still waiting for approval is not published, and fails the job.

## A new npm package

npm attaches a trusted publisher only to a package that exists, so a package's first version is published by hand, from a terminal logged in with `npm login` (the 2FA prompt needs a real TTY):

```sh
pnpm --filter <name> build && cd <package dir> && npm publish --access public
npm trust github <name> --file release.yml --repo <owner>/<repo> --env npm --allow-publish --allow-stage-publish -y
npm trust list <name>
```

`--file` is the workflow file holding the publish job (the stub's name, `cli-release.yml` for e-id's CLI) and `--env` its environment; both must match the stub, or CI's publish fails with a 404 from npm. From then on CI publishes every version: the next push finds the version on npm and only writes the release.

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
      - uses: adriangalilea/ci/.github/actions/npm-publish@<sha> # v1.6.0

  release:
    needs: [build, publish]
    uses: adriangalilea/ci/.github/workflows/release.yml@<sha> # v1.0.0
    with:
      tag: ${{ needs.build.outputs.tag }}
    permissions:
      contents: write
```

### Node package inside a repo (npm)

A package that is not the repo but lives in it (e-id's `cli/`), built against the repo's dependencies and types: the repo's root installs and runs `verify` as above, then the package is built and packed in `directory`. Its tags carry `tag-prefix` (`cli-v0.1.0`), so they are never the repo's own `v…`, and its notes list only the commits that touched `paths`. `bun: true` sets up Bun for a build script that runs it. `verify: <script>` runs a root script of the package's own instead of the repo's whole `verify`, where that cannot run in CI (e-id's site needs a key to open its sealed paid components; its CLI is checked by `verify:cli`, and the site by its own deploy). The trusted publisher on npm names this file (`cli-release.yml`), not `release.yml`. Run it only when the package changed:

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
    uses: adriangalilea/ci/.github/workflows/node.yml@<sha> # v1.4.0
    with:
      directory: cli
      tag-prefix: cli-
      bun: true
      verify: verify:cli
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

Several packages in one repo (ts-utils) repeat that chain per package in one `release.yml`, each build with its own `artifact`, each publish job passing it to `actions/npm-publish`, and each release needing only its own build and publish. One publish job with a matrix would couple them: `needs` waits on the whole matrix, so one package's failed publish would skip every package's release.

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
