# AGENTS.md — layer-docs-site

Standalone candy repo for the `docs-site` layer — the Astro + Starlight toolchain
that clones the published `opencharly/docs` repo at a pinned commit and builds
the production site inside a box, plus the `docs-site-app` box and the
`check-docs` `disposable: true` bed. The candy, box, and bed all live in
`charly.yml` at the repo root; the embedded `skill:` entity is projected into the
marketplace corpus as `/charly-tools:docs-site`.

Canonical files:

- `charly.yml` — the `docs-site:` candy entity, the `docs-site-app:` box, the
  `check-docs:` bed, and the `docs-site-skill:` skill entity.
- `CHANGELOG/` — per-CalVer release history.
- `.github/workflows/tag-on-merge.yml` — CalVer tag + `CHANGELOG/` on merge.
- `README.md` — user overview only; never agent guidance.

## Load these skills first (R0)

- `/charly-tools:docs-site` — the owning skill. The clone-at-pinned-commit model,
  the two `DOCS_REF` occurrences, the site-shape checks, and the `check-docs`
  bed. Load before editing or troubleshooting the layer.
- `/charly-check:check` — the check/bed model and the check-verb catalog. Load
  before changing any `check:` step or the bed.
- `/charly-image:layer` — the candy authoring reference (`charly.yml` schema,
  `plan:` step verbs, `var:` substitution, `shell:`/`service:` blocks). Load
  before editing any entity field or plan step.

## Build / validate / test

- The merge gate is the **org-wide** `charly/pr-validator` (required check
  `validate / validate`, defined in `opencharly/.github`); this repo has **no
  per-repo candy gate** and ships only `.github/workflows/tag-on-merge.yml`.
- The candy's `plan:` `check:` steps are the functional evidence and run in BOTH
  `build` and `runtime` contexts, so `charly check box docs-site-app` proves the
  site builds without deploying. `docs-site-runtime-plugin-page` is the
  load-bearing one: it fails if the generator ever documents only the
  default-active plugin set.
- The `check-docs` bed is the `disposable: true` pod deploy of `docs-site-app`;
  run it with `charly check run check-docs`.

## Modify this repo

- Edit the `docs-site:` candy entity AND the `docs-site-skill:` skill entity in
  `charly.yml` together. The skill is the projected usage source, so a var,
  check, or behaviour change not mirrored in the skill leaves the corpus stale.
- `DOCS_REF` is an **immutable commit, never a branch**, and it appears TWICE —
  once as the clone's cache key and once as a literal in the
  `docs-site-pinned-commit` check's `contains:` matcher. A check step's
  substitution does not resolve a candy `var:`, so the matcher cannot use
  `${DOCS_REF}`; the duplication is deliberate and both occurrences must be
  updated together.
- New behaviour claims belong in the `plan:` as an observable `check:` step, and
  in the skill body.

## Landing

- PR-only. Every change lands through a pull request; the org-required
  `charly/pr-validator` validates the diff and body and arms native auto-merge
  on PASS. Direct pushes to `main` are blocked.
- History lives in `CHANGELOG/` (written by `tag-on-merge` at merge time); the
  PR body IS the changelog.
- The authoritative rulebook is the umbrella `AGENTS.md` in
  `opencharly/opencharly` and `charly/AGENTS.md` in the charly repo. Do not
  restate its rules here.
