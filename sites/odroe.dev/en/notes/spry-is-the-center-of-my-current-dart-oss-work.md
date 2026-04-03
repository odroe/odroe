---
title: Spry Is the Center of My Current Dart OSS Work
description: How Spry, Alien Signals, and Oref fit together in the current public Odroe project line.
---

This note explains the current center of gravity behind my Dart open-source work.

Use it as the long-form companion to the current project entry on [odroe.dev](/) and [/packages](/packages/).

## Why this line needed to become explicit

Over the last few years, I shipped many open-source experiments across Dart and Flutter.

That created a real problem: too many things were visible at once, but not enough of them formed a clear current direction.

So I started narrowing the focus.

Right now the center of that work is `Spry`.

`Spry` is a file-routing server framework for teams that want one codebase across Dart VM, Node.js, Bun, Deno, Cloudflare Workers, Vercel, and Netlify. It keeps the authoring model small, keeps generated output explicit and inspectable, and can generate OpenAPI documents plus typed clients from the same source tree.

That combination matters to me more than adding one more abstraction layer.

I want a framework that stays close to the filesystem, makes deployment targets a build concern instead of a rewrite, and keeps the generated runtime visible instead of hiding everything behind a giant DSL.

That is why `Spry` is the current center of gravity.

It is not only a package. It is the project that can anchor documentation, examples, starter templates, deployment guides, AI-assisted tooling, and a clearer public story around what I am actually building now.

## Why Spry comes first

There are three reasons I am pushing `Spry` to the front.

### First, the user value is clear

You can explain `Spry` in one sentence: file routing, explicit output, cross-runtime deployment, and OpenAPI plus typed client generation from one Dart project.

A concrete example makes that easier to evaluate.

I want a team to start with a file-routed API on Dart VM, keep the same route tree when shipping to Cloudflare Workers or Bun, and still generate `openapi.json` plus typed clients from the same project. That is the kind of workflow I want `Spry` to make boring.

### Second, it creates leverage

If `Spry` gets better, everything around it becomes easier to explain: starter repos, runtime adapters, documentation, debugging workflows, and future integrations for AI-assisted DX.

### Third, it gives me a better operating model

Instead of maintaining scattered experiments with weak entry points, I can organize current work around one project with a strong surface area and a concrete roadmap.

## Where Alien Signals and Oref fit

This does not mean everything else disappears.

`alien-signals-dart` and `oref` are still part of the current focus, but they play different roles.

`alien-signals-dart` is the reactive core.

It gives Dart a small, high-performance reactive system with `signal()`, `computed()`, and `effect()` primitives. I see it as infrastructure: small surface area, composable design, and performance without unnecessary ceremony.

`oref` is where that philosophy becomes a Flutter developer experience.

Built on top of `alien_signals`, `oref` turns signal-based state into something ergonomic in real Flutter apps. It is not just another state management package for the sake of having one. It is a practical expression of the same preference for directness, less boilerplate, and inspectable behavior.

So the way I think about the current portfolio is simple:

- `Spry` is the framework line and the main public entry.
- `alien-signals-dart` is the reactive core line.
- `oref` is the Flutter-facing application of that reactive model.

They are not identical projects, but they are coherent projects.

## What I am building around Spry next

The next step is not to make more noise. It is to make `Spry` easier to enter, easier to adopt, and easier to extend.

That means:

1. tightening the docs and examples around the real starting path;
2. improving the runtime and deployment story across targets;
3. building first-party AI-assisted workflows around docs, debugging, and project scaffolding;
4. keeping the generated output and framework behavior inspectable instead of magical.

I already have open work around AI-assisted DX, including first-party docs, debugging skills, an optional MCP server path, and a first-party plugin direction for coding agents.

Those are not side quests.

They are part of the same idea: if framework ergonomics matter, then the tooling around understanding, generating, and debugging a project matters too.

## What to expect from future writing

Going forward, I want long-form writing to be the place where I explain the deeper reasoning behind these projects instead of only posting fragmented updates.

So the writing cadence will follow three tracks:

- project notes around `Spry`, `alien-signals-dart`, and `oref`;
- architecture notes about runtime design, reactivity, and framework tradeoffs;
- open source operations notes about shipping, maintenance, and AI-assisted tooling.

The short version is still the same:

`Spry` is the center of my current Dart OSS work because it creates the clearest user value, the strongest leverage, and the most coherent next step for everything else I am building.

If this line of work is relevant to you, the best way to follow it is simple: start with `Spry`, then look at `alien-signals-dart` and `oref` as the reactive and Flutter-facing parts of the same broader direction.

## Start here

- [Odroe project entry](/packages/)
- [Spry](https://github.com/medz/spry)
- [Alien Signals for Dart](https://github.com/medz/alien-signals-dart)
- [Oref](https://github.com/medz/oref)
- [Medium author page](https://shiwei.medium.com/)
