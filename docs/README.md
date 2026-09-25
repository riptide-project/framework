# Riptide documentation

This is the English documentation site for Riptide. It runs on Astro and Starlight and serves all supported releases from one GitHub Pages site.

## Run locally

From this directory:

```bash
npm ci
npm run dev
```

Build the static site with `npm run build`. The output is in `dist/`.

## Version layout

- `src/content/docs/index.mdx` is the product overview and points new readers to the latest stable release while linking to the Maelstrom-3 preview.
- `src/content/docs/versions/index.md` lists all documented releases.
- `src/content/docs/versions/<version>/` holds documentation for that exact release.
- Versions `0.3.0` through `0.7.1` have release-specific guides and API pages based on their tagged README, changelog, and source. Historical README guides are adapted for correct installation and omit framework development instructions.
- Versions `0.8.0` through `0.8.2` contain snapshots of the docs from their tags. The `0.8.2` snapshot is supplemented with a shorter first-run guide, a learning path, and an example.
- `0.9.0-maelstrom.2` is the earlier preview. `0.9.0-maelstrom.3` has its own preview installation, API, examples, and migration documentation. Version `0.8.2` is the latest stable release.

Every versioned Markdown file declares an explicit `slug` in frontmatter. This keeps dots in version numbers in the URL; Astro's generated IDs would otherwise remove them. Keep the slug in sync with the file's path when moving or adding a page.

## Adding a release

1. Add a directory under `src/content/docs/versions/` with the documentation for the tagged release. Preserve old release docs rather than applying current API changes to them.
2. Add explicit `slug` values to its Markdown and MDX files.
3. Add the release to `src/versions.ts`, `src/content/docs/versions/index.md`, and the sidebar in `astro.config.mjs`.
4. If it is the new latest stable release, update the overview page and first-run links to point to it.
5. Run `npm run build` and check both the new release pages and links between versions.

The project home is the version-neutral overview. Every release has a consistent landing page for that release's guides. The selector in `src/components/VersionSelect.astro` tries to keep readers on the same page when switching between versions. If the destination release has no matching page, it opens that release's landing page.

The deployment workflow builds this unified site from `maelstrom`, which contains both stable and canary documentation. Version `0.8.2` remains the default stable learning path. Keep one deployment branch so an older stable checkout cannot overwrite newer version pages. Manual workflow runs must also select `maelstrom`. Local builds and dev-server runs do not publish it.

Allow `maelstrom` in the `github-pages` environment deployment rules. When merging workflow changes into `main`, preserve this deployment branch until the unified documentation is intentionally moved. See [the release checklist](../scripts/RELEASING.md) for package publication.
