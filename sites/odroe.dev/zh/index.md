---
title: "提供开源的 Dart 和 Flutter 应用程序中的反应式编程和依赖注入以及各种实用程序和工具。"
layout: home
hero:
  name: Odroe
  text: 利用 Odroe 生态系统释放 Dart/Flutter 的潜力
  tagline: Dart/Flutter 库、工具和实用程序，旨在提升您的编码之旅。
  image:
    light: /hero-light.png
    dark: /hero-dark.png
  actions:
    - theme: brand
      text: "探索 Odroe 生态 →"
      link: https://github.com/odroe
features:
  - title: Oref
    details: Oref is a lightweight, high-performance reactive programming library.
  - title: Oinject
    details: A lightweight dependency injection package for Flutter, simplifying state and service management across widgets.
  - title: Oncecall
    details: Oncecall is a memoization tool for use in the build method of Widgets.
  -
    icon:
      src: https://prisma.pub/prisma-dart.logo.svg
    title: Prisma Dart
    details: Prisma Client Dart is an auto-generated type-safe ORM.
    link: https://prisma.pub
  - icon:
      src: https://spry.fun/spry.svg
    title: Spry
    details: A lightweight, composable Dart web framework designed to work collaboratively with various runtime platforms.
    link: https://spry.fun
  - icon: 🛸
    title: Routing Kit
    details: Lightweight and fast router for Dart.
    link: https://github.com/medz/routingkit
---

<script setup>
import { VPTeamPageTitle, VPTeamMembers } from 'vitepress/theme';
import members from '../.vitepress/data/members';
</script>

<VPTeamPageTitle>
  <template #title>
    Our Team
  </template>
</VPTeamPageTitle>

<VPTeamMembers size="small" :members="members" />

<VPTeamPageTitle>
  <template #title>
    Made by community
  </template>
  <template #lead>
    Say hello to our awesome contributors.
  </template>
</VPTeamPageTitle>

<a href="https://github.com/odroe/odroe/graphs/contributors" >
  <img src="https://contrib.rocks/image?repo=odroe/odroe" style="margin: 0 auto;" />
</a>
