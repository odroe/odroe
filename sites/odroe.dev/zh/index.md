---
title: "提供开源的 Dart 和 Flutter 应用程序中的反应式编程和依赖注入以及各种实用程序和工具。"
layout: home
hero:
  name: 利用 Odroe 生态系统释放 Dart/Flutter 的潜力
  tagline: Dart/Flutter 库、工具和实用程序，旨在提升您的编码之旅。
  image:
    light: /hero-light.png
    dark: /hero-dark.png
  actions:
    - theme: brand
      text: "探索 Odroe 生态 →"
      link: https://github.com/odroe
  what-is-new:
    title: Odroe 生态正在建设中，请在 GitHub 给我们一个 🌟
    link: https://github.com/odroe/odroe
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
