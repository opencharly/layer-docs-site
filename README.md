# docs-site

The Astro + Starlight toolchain for the [opencharly.ai](https://opencharly.ai)
documentation site, plus a production build of the published site itself.

`docs-site` clones the [opencharly/docs](https://github.com/opencharly/docs)
repository at an immutable pinned commit, runs a clean `npm ci` against its
committed lockfile, and builds the production site into `/srv/docs/dist`. A build
failure — a bad frontmatter scalar, a Starlight config a version bump
invalidated, a page whose markdown will not parse — fails the **image build**,
which builds from the same input Cloudflare Pages does, so the box catches it
before a deploy can. The checks assert the built site's **shape**, not merely its
existence.

## What it provides

| Property | Value |
|---|---|
| Layer / candy | `docs-site` |
| Requires | `layer-nodejs` (`@github.com/opencharly/layer-nodejs`) |
| Packages | `git` (fedora section) |
| Builds into | `/srv/docs` (source), `/srv/docs/dist` (built site) |
| Consumed by | the `docs-site-app` box → the `check-docs` bed |
| Service / port | none |

Why it clones the published repo: the docs repo is standalone (charly no longer
carries it as a submodule), and a candy cannot read a sibling directory (`..` is
rejected at validate time). Cloning the published repository is the schema-legal
path, and it tests the more useful thing — the exact source Cloudflare builds. It
fetches an immutable commit, never a branch: that is what keeps the clone layer's
cache key moving with the pin.

## How to use it

Compose the layer by pinning this repo in a box's `candy:` list, or use the
shipped `docs-site-app` box:

```yaml
docs-site-app:
  candy:
    base: quay.io/fedora/fedora:43
    candy:
      - '@github.com/opencharly/layer-docs-site:v2026.269.1347'
```

Verify without deploying — every check is build-context, so
`charly check box docs-site-app` proves the whole site builds and has the right
shape:

```bash
charly check box docs-site-app
```

The load-bearing check is `docs-site-runtime-plugin-page`: it reads the page of
`plugin-cdp`, which is **not** compiled into the charly binary, and asserts both
its rendered placement and its CUE parameter schema — so the bed fails if the
generator ever narrows to documenting only the default-active set.

## Layout

- `charly.yml` — the `docs-site:` candy entity, the `docs-site-app:` box, the
  `check-docs:` `disposable: true` bed, and the embedded `docs-site-skill:`
  skill entity.
- `CHANGELOG/` — per-CalVer release notes.
- `.github/workflows/tag-on-merge.yml` — CalVer tag + `CHANGELOG/` on merge.
- `README.md` — this user overview.

## Related

- Owning skill: `/charly-tools:docs-site`
- Generator: `/charly-build:docs` — the `charly docs generate` verb that produces
  the content this builds
- Node runtime: `/charly-coder:nodejs`
- Bed model: `/charly-check:check`
- [`opencharly/docs`](https://github.com/opencharly/docs) — the published site repo
- [`opencharly/charly`](https://github.com/opencharly/charly) — the charly CLI and image builder
- [`opencharly/opencharly`](https://github.com/opencharly/opencharly) — the umbrella
