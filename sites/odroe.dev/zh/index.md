---
title: 开源的 Dart 和 Flutter 应用程序中的反应式编程和依赖注入以及各种实用程序和工具。
layout: home
hero:
  name: 利用 Odroe 生态系统释放 Dart/Flutter 的潜力
  tagline: Dart/Flutter 库、工具和实用程序，旨在提升您的编码之旅。
  image:
    light: /hero-light.png
    dark: /hero-dark.png
  actions:
    - theme: brand
      text: 探索 Odroe 生态 →
      link: ./packages/
  what-is-new:
    title: Odroe 生态正在建设中，请在 GitHub 给我们一个 🌟
    link: https://github.com/odroe/odroe
features:
  - icon: >-
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="size-6">
        <path stroke-linecap="round" stroke-linejoin="round" d="m21 7.5-9-5.25L3 7.5m18 0-9 5.25m9-5.25v9l-9 5.25M3 7.5l9 5.25M3 7.5v9l9 5.25m0-9v9" />
      </svg>
    title: 高品质、单一用途
    details: 每个包都经过精心制作并专注于特定功能，使其易于理解与实用。
  - icon: >-
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="size-6">
        <path stroke-linecap="round" stroke-linejoin="round" d="M18 18.72a9.094 9.094 0 0 0 3.741-.479 3 3 0 0 0-4.682-2.72m.94 3.198.001.031c0 .225-.012.447-.037.666A11.944 11.944 0 0 1 12 21c-2.17 0-4.207-.576-5.963-1.584A6.062 6.062 0 0 1 6 18.719m12 0a5.971 5.971 0 0 0-.941-3.197m0 0A5.995 5.995 0 0 0 12 12.75a5.995 5.995 0 0 0-5.058 2.772m0 0a3 3 0 0 0-4.681 2.72 8.986 8.986 0 0 0 3.74.477m.94-3.197a5.971 5.971 0 0 0-.94 3.197M15 6.75a3 3 0 1 1-6 0 3 3 0 0 1 6 0Zm6 3a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Zm-13.5 0a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Z" />
      </svg>
    title: 协作与社区
    details: 张开双臂欢迎新想法、反馈和代码贡献，一起组建具有创新和可靠的开源社区。
  - icon: >-
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="size-6">
        <path stroke-linecap="round" stroke-linejoin="round" d="M6.429 9.75 2.25 12l4.179 2.25m0-4.5 5.571 3 5.571-3m-11.142 0L2.25 7.5 12 2.25l9.75 5.25-4.179 2.25m0 0L21.75 12l-4.179 2.25m0 0 4.179 2.25L12 21.75 2.25 16.5l4.179-2.25m11.142 0-5.571 3-5.571-3" />
      </svg>
    title: 一致性
    details: 每个包都遵循最佳实践并切割为易用的 API 和低级函数，确保顺利组合的兼容性。
---

<script setup>
import { VPTeamPageTitle, VPTeamMembers } from 'vitepress/theme';
import members from '../.vitepress/data/members';
</script>

<VPTeamPageTitle>
  <template #title>
    认识一下团队成员
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
  <img src="https://contrib.rocks/image?repo=odroe/odroe" class="mx-auto" />
</a>
