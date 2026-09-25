# Releasing Riptide

## One-time setup

Set repository Actions secrets `PESDE_TOKEN` and `WALLY_TOKEN` to credentials accepted by the respective registries for an owner of the `riptide` scope. The workflow uses `pesde auth login --token` and `wally login --token`; the built-in `GITHUB_TOKEN` is only used for the GitHub release. Never commit tokens or paste them into release notes.

To reuse a local registry login:

- Pesde: run `pesde auth login` and authorize the scope owner's GitHub account. `pesde auth token` prints the saved credential in your own terminal; copy it into `PESDE_TOKEN`. The publication helper accepts either the full `Bearer ...` credential or a raw GitHub token.
- Wally: run `wally login` and authorize the scope owner's GitHub account. Copy the matching registry's token value from `~/.wally/auth.toml` into `WALLY_TOKEN` (on Windows, `%USERPROFILE%\.wally\auth.toml`). Copy the value only, without TOML quotes or a `Bearer` prefix.

Add each value in the repository's **Settings → Secrets and variables → Actions → New repository secret**. Do not share the token output or authentication file in chat. The credential's GitHub account must own the registry scope; repository write access alone does not grant package publication rights.

Enable GitHub Pages through Actions and allow `maelstrom` in the `github-pages` environment deployment rules. This branch owns the unified stable/canary documentation site. Carry the same deployment workflow into `main` so its previous workflow no longer deploys an older copy of the site.

## Before tagging

1. Fix release blockers and run CI on the exact commit to be tagged.
2. Keep Pesde, Wally, the changelog and versioned docs on the same version.
3. Replace the top changelog's `Unreleased` marker with the actual release date. Update the README and version pages from "upcoming/not published" to released wording when preparing publication.
4. Commit all source, tests, scripts, workflows and versioned docs. Untracked files are not included by a tag.
5. Push the matching tag, such as `v0.9.0-maelstrom.3`.

The release workflow validates metadata and credentials, runs the full CI workflow, then publishes Pesde and Wally in separate jobs. It requires a positive registry acknowledgement because these CLI versions can return exit code zero after reporting a publication error. Only after both jobs succeed does it publish the GitHub release and `.rbxm`. Versions containing a prerelease suffix are marked as GitHub prereleases and are not made latest.

## Recovery

If one registry succeeds and the other fails, use **Re-run failed jobs**, so the already published package is not uploaded again. The same applies if only the GitHub release job fails. Do not rerun every job or move a released tag: registry versions are immutable. If a job loses its response after the registry accepted the upload, inspect the registry before retrying and reconcile the published version manually.

Preparing these files does not publish anything. Registry authentication and the complete hosted workflow can only be verified with configured secrets and a release tag.
