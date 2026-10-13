# ci

Shared GitHub Actions workflows for adriangalilea's packages: build, verify, and release notes in one place. Each repo keeps a short `release.yml` stub that calls these.

| Workflow | Does | Outputs |
|---|---|---|
| `python.yml` | `uv sync`, `ruff check`, `ruff format --check`, `uv build`, uploads `dist` | `tag`, `release` |
| `node.yml` | `pnpm install`, `pnpm run verify`, `pnpm run build`, `pnpm pack`, uploads `dist` | `tag`, `release` |
| `swift.yml` | `swift build -c release`, `swift test` | |
| `release.yml` | git-cliff notes for `<previous semver tag>..HEAD`, then tag + GitHub release in one call, optional assets from an artifact | |

## Why the publish job stays in each repo

PyPI and npm trusted publishing check the workflow file of the repo that publishes. A publish step inside a reusable workflow from another repo fails that check. So the stub owns the one job that holds `id-token: write`, and that job runs no project code: it downloads the artifact the read-only build job produced and uploads it.

## Idempotency

The GitHub release is the last step, and its absence is what triggers a run: `release` is true on a push to the default branch when `v<version>` has no release. Publishing skips a version the registry already has. A run that died after publishing is finished by the next push.

## Pinning

Callers pin to a full commit SHA with the version in a comment, and Dependabot (`github-actions` ecosystem) opens a PR when this repo tags a new version. Every action used here is pinned the same way.

Cut a version: `git tag v1.2.3 && git push --tags`.

## Stubs

### Python (PyPI)

Trusted publisher on PyPI: workflow `release.yml`, no environment. ruff must be a dependency of the project (`[dependency-groups] dev = ["ruff"]`).

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
          TGZ=$(echo dist/*.tgz)
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
