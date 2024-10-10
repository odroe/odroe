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
    details: Oref 是一个轻量级、高性能的反应式编程库。
  - title: Oinject
    details: Flutter 的轻量级依赖注入工具，简化跨小部件的状态和服务管理。
  - title: Oncecall
    details: Oncecall 是一个用于 Widget.build 方法的记忆工具。
  -
    icon:
      src: https://prisma.pub/prisma-dart.logo.svg
    title: Prisma Dart
    details: Prisma Dart 是一个自动生成的类型安全的 ORM。
    link: https://prisma.pub
  - icon:
      src: https://spry.fun/spry.svg
    title: Spry
    details: 轻量级、可组合的 Dart 网络框架，旨在与各种运行时平台协同工作。
    link: https://spry.fun
  - icon: 🛸
    title: Routing Kit
    details: 适用于 Dart 的轻量级且快速的路由器。
    link: https://github.com/medz/routingkit
---

<script setup>
import { VPTeamPageTitle, VPTeamMembers } from 'vitepress/theme';
import members from '../.vitepress/data/members';
</script>

<VPTeamPageTitle>
  <template #title>
    认识一下我们的团队成员
  </template>
</VPTeamPageTitle>

<VPTeamMembers size="small" :members="members" />

<VPTeamPageTitle>
  <template #title>
    由社区制作
  </template>
  <template #lead>
    向我们出色的贡献者问好。
  </template>
</VPTeamPageTitle>

<a href="https://github.com/odroe/odroe/graphs/contributors" >
  <img src="https://contrib.rocks/image?repo=odroe/odroe" style="margin: 0 auto;" />
</a>
