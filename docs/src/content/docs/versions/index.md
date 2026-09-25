---
slug: versions
title: Documentation versions
description: Choose the Riptide documentation that matches the version installed in your game.
---

Choose the same version as your installed package. For a new game, begin with **0.8.2**, the latest stable release. Maelstrom-3 is the latest preview release.

## Current choices

| Release | Channel | Start here |
| --- | --- | --- |
| **0.8.2** | Latest stable | [Your first 10 minutes](./0.8.2/guides/quickstart/) |
| **0.9.0-maelstrom.3** | Latest preview | [Preview documentation](./0.9.0-maelstrom.3/) |
| **0.9.0-maelstrom.2** | Earlier preview | [Release docs](./0.9.0-maelstrom.2/) |

## Earlier stable releases

| Release | Documentation |
| --- | --- |
| 0.8.1 | [Release guides and API](./0.8.1/) |
| 0.8.0 | [Release guides and API](./0.8.0/) |
| 0.7.1 | [Release guides and API](./0.7.1/) |
| 0.7.0 | [Release guides and API](./0.7.0/) |
| 0.6.0 | [Release guides and API](./0.6.0/) |
| 0.5.0 | [Release guides and API](./0.5.0/) |
| 0.4.0 | [Release guides and API](./0.4.0/) |
| 0.3.0 | [Release guides and API](./0.3.0/) |

Releases before 0.8.0 have separate getting-started, lifecycle, networking, and component pages written from their tagged README and source. Their historical guides are adapted for correct installation and omit framework development instructions. The 0.8.x guides and API pages document their respective releases. Maelstrom-3 has its own installation guide, API reference, examples, and migration guides.

## Package manager availability

| Releases | Package route |
| --- | --- |
| 0.3.0–0.4.0 | Wally: `thereplicatedfirst/riptide` |
| 0.5.0 | Pesde: `riptide/core`; Wally: `thereplicatedfirst/riptide` |
| 0.6.0–0.8.0 | Pesde: `riptide/core`; no Wally package for these versions |
| 0.8.1–0.8.2 | Pesde: `riptide/core`; Wally manifests exist in the source tags, but these versions are absent from the Wally index |
| 0.9.0-maelstrom.2 | Pesde and Wally: `riptide/core` |
| 0.9.0-maelstrom.3 | Pesde and Wally: `riptide/core` |

Earlier tagged releases have a `Riptide.rbxm` asset on GitHub. The 0.3.0 tag's README and `wally.toml` use `riptide-project/riptide`, but the published Wally entry is under `thereplicatedfirst/riptide`.

Package availability was checked against the [Pesde index](https://github.com/pesde-pkg/index/blob/main/riptide/core) and the Wally index entries for [the old scope](https://github.com/UpliftGames/wally-index/blob/main/thereplicatedfirst/riptide) and [the Maelstrom scope](https://github.com/UpliftGames/wally-index/blob/main/riptide/core).
