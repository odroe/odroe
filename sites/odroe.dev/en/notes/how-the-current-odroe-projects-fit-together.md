---
title: How the Current Odroe Projects Fit Together
description: A portfolio-level guide to where Spry, Alien Signals, Oref, and the older reference docs fit inside the current Odroe public entry.
---

This note is the portfolio-level companion to the current [Odroe project entry](/packages/).

If you want the shorter project-level explanation for why `Spry` sits at the center right now, read [Spry Is the Center of My Current Dart OSS Work](/notes/spry-is-the-center-of-my-current-dart-oss-work).

Prefer Chinese? Read the [Chinese version](/zh/notes/how-the-current-odroe-projects-fit-together).

## Why this needed its own note

If you land on Odroe today, you can see two different kinds of things at once:

- the projects that represent the current public direction;
- the older package docs that still have reference value.

That split is intentional.

Over the years, I shipped many open-source repos, packages, and experiments. Keeping all of them equally visible made the public entry harder to understand. It was easy to mistake "still hosted" for "still central."

So the current Odroe entry is built around a simpler rule:

- show the projects that matter now first;
- keep useful historical docs accessible without pretending they are all equally active.

## The current public line in one view

Right now, the clearest way to read the current Odroe line is this:

- `Spry` is the main framework line and the first project most people should start from.
- `alien-signals-dart` is the reactive core line.
- `oref` is the Flutter-facing expression of that reactive direction.

These are not random repos placed next to each other for convenience.

They are the projects that best explain what Odroe is building in public right now: practical developer tooling, reactive foundations, and framework work that can keep expanding through docs, starters, examples, and AI-assisted workflows.

## Where to start based on what you need

The best starting point depends on what you are trying to evaluate.

### Start with Spry if you want the framework story

Start with [`Spry`](https://github.com/medz/spry) if you care about:

- file-routed Dart server tooling;
- shipping one codebase across runtimes;
- keeping generated output explicit instead of magical;
- generating OpenAPI documents and typed clients from the same project.

This is the clearest current entry because it carries the strongest product surface, the strongest documentation leverage, and the strongest long-term narrative for the rest of the portfolio.

### Start with Alien Signals if you want the reactive core

Start with [`alien-signals-dart`](https://github.com/medz/alien-signals-dart) if you care about:

- small reactive primitives for Dart and Flutter;
- signals-style state and derivation;
- lower-level building blocks instead of a large framework.

This is where the reactivity line stays compact and technical.

### Start with Oref if you want the Flutter-facing layer

Start with [`oref`](https://github.com/medz/oref) if you care about:

- a more ergonomic Flutter-facing reactive experience;
- applying signals-style ideas in app code;
- understanding how the reactive core becomes practical developer experience.

`oref` matters because it keeps the current line from collapsing into a server-only story. It shows how the same preferences can become a usable Flutter workflow.

## Why older package docs are still here

Some older package pages remain on odroe.dev because they still have reference value.

That does not automatically make them current flagship projects.

The rule is straightforward:

- current projects should shape the public entry;
- reference projects should stay readable without competing for the same top-level attention.

That is why pages like `Oinject` and `Once Call` still exist, but they are now presented as reference docs instead of the main story.

## What Odroe is actually doing as a public entry

Odroe is not meant to be a random repo directory.

It is the brand and public entry that should help people answer four questions quickly:

1. What is being built now?
2. Which projects matter first?
3. What is current versus reference-only?
4. Where should I go next?

That is also why the core repos do not all need to live under the same GitHub organization to form one coherent public line. The public experience starts from Odroe, then branches into the right project entry.

## How to follow the longer thread

Use the channels for different depths:

- start with the [homepage](/) for the shortest brand and project entry;
- use [/packages](/packages/) for the project-level portfolio view;
- read [Spry Is the Center of My Current Dart OSS Work](/notes/spry-is-the-center-of-my-current-dart-oss-work) for the current center of gravity;
- follow [@OdroeDev](https://x.com/OdroeDev) for shorter public updates;
- use [Medium](https://shiwei.medium.com/) as the mirrored long-form channel.

The main point is simple:

Odroe should help people understand the current project line faster, not make them reverse-engineer it from a flat repo list.
