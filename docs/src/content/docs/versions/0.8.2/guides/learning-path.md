---
slug: versions/0.8.2/guides/learning-path
title: Learning path
description: A route from your first service to production-ready Riptide features.
---

You do not need to learn every Riptide API before you build a game. Follow the stages that match what you are making.

## 1. First run

Start with [Your first 10 minutes](../quickstart/). You will install Riptide in Studio, create one server service, and see its `Init` and `Start` methods run.

**You are ready for the next stage when:** you can explain what the entry script launches and where service modules live.

## 2. Organize your game

Read [Project Structure](../project-structure/) and [Module Lifecycle](../module-lifecycle/). Create two services and look one up from the other during `Init`. Keep game logic in modules and keep the launch script small.

**You are ready for the next stage when:** you can find a service with `GetService` and know which work belongs in `Init` versus `Start`.

## 3. Connect server and client

Complete the [full setup guide](../getting-started/) to add a client controller. Then follow the [player state example](../../examples/player-coins/) to send server-owned data to the client.

Read the [Network](../../api/network/) and [State Replication](../../api/state-replication/) references when you need communication or reactive UI.

## 4. Grow safely

Use [Component Service](../../api/component-service/) for behavior attached to tagged Roblox instances. Use [Player Lifecycle](../../api/player-lifecycle/) for joining and leaving players. Review the [Utilities](../../api/utilities/) and [State Machine](../../api/state-machine/) references when your game's complexity calls for them.

:::tip[Working with the preview]
The [Maelstrom-3 preview](../../../0.9.0-maelstrom.3/) has different APIs. Switch the documentation version before copying examples.
:::
