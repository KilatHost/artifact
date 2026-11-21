# Releasing

Releases are cut by maintainers. Pushing a `vX.Y.Z` tag runs
`.github/workflows/release.yml`, which:

1. Checks that the tag, `VERSION`, the image default in `compose.yaml`,
   `ARTIFACT_VERSION` in `.env.example` and a dated `CHANGELOG.md` entry agree.
2. Runs the full CI workflow (tests, lint, Compose smoke check).
3. Builds `linux/amd64` and `linux/arm64` images on native runners and pushes
   `ghcr.io/kilathost/artifact:X.Y.Z`, `:X.Y` and `:X`.
4. Creates a **draft** GitHub release with the changelog entry, the image digest,
   a source archive and `SHA256SUMS`.

## Before tagging

- [ ] The release's go/no-go gates in the launch plan have passed, including the
      cross-client MCP check, and the README claims only the clients and auth paths
      that passed.
- [ ] A fresh Linux install from the README quick start, an upgrade from the
      previous release and a restore from backup have been run as written in
      `deploy.md`.
- [ ] In one pull request: set `VERSION`, the `ARTIFACT_VERSION` default in
      `compose.yaml` (both services) and `.env.example`, and replace `Unreleased`
      with the date in the version's `CHANGELOG.md` heading. Merge it to `main`.

## Tag

```sh
git checkout main && git pull
git tag -a v1.0.0 -m "Kilat Artifact 1.0.0"
git push origin v1.0.0
```

## After the workflow passes

1. First release only: in the organization's **Packages**, open `artifact`,
   connect it to the `KilatHost/artifact` repository if it is not already, and set
   its visibility to **Public** so `docker compose pull` works without logging in.
2. From a machine that is not logged in to GHCR, check both architectures and the digest:

   ```sh
   docker buildx imagetools inspect ghcr.io/kilathost/artifact:1.0.0
   ```

   The top-level digest must match `artifact-1.0.0-image-digest.txt`, and
   `sha256sum -c SHA256SUMS` must pass on the downloaded release assets.
3. Review and publish the draft release.
4. Open a pull request that adds an empty `## [Unreleased]` section to the top of
   `CHANGELOG.md`.

If the workflow fails after pushing images, fix the problem on `main` and release
the next patch version. Do not move or reuse a published tag.
