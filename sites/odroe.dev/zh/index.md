---
title: 面向多运行时交付团队的 Spry 优先 Dart 基础设施。
layout: home
hero:
  name: 面向多运行时交付团队的 Spry 优先 Dart 基础设施。
  tagline: Odroe 围绕 Spry、Oref 与务实的 AI 辅助开发体验构建，让同一套 Dart 代码库可以运行在 Dart VM、Node.js、Bun、Deno、Cloudflare Workers、Vercel 与 Netlify。
  image:
    light: /hero-light.png
    dark: /hero-dark.png
  actions:
    - theme: brand
      text: 从 Spry 开始 →
      link: https://spry.medz.dev/getting-started
    - theme: alt
      text: 浏览 Packages
      link: /zh/packages/
  what-is-new:
    title: 当前重点：文件路由服务端、响应式基础能力，以及便于 AI 协作的可检查产物。
    link: https://github.com/medz/spry
features:
  - icon: >-
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="size-6">
        <path stroke-linecap="round" stroke-linejoin="round" d="m21 7.5-9-5.25L3 7.5m18 0-9 5.25m9-5.25v9l-9 5.25M3 7.5l9 5.25M3 7.5v9l9 5.25m0-9v9" />
      </svg>
    title: 用 Spry 构建文件路由服务端
    details: 直接用文件系统定义路由，保持部署目标灵活，让运行时代码保持可见，而不是被巨大的 DSL 隐藏起来。
  - icon: >-
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="size-6">
        <path stroke-linecap="round" stroke-linejoin="round" d="M18 18.72a9.094 9.094 0 0 0 3.741-.479 3 3 0 0 0-4.682-2.72m.94 3.198.001.031c0 .225-.012.447-.037.666A11.944 11.944 0 0 1 12 21c-2.17 0-4.207-.576-5.963-1.584A6.062 6.062 0 0 1 6 18.719m12 0a5.971 5.971 0 0 0-.941-3.197m0 0A5.995 5.995 0 0 0 12 12.75a5.995 5.995 0 0 0-5.058 2.772m0 0a3 3 0 0 0-4.681 2.72 8.986 8.986 0 0 0 3.74.477m.94-3.197a5.971 5.971 0 0 0-.94 3.197M15 6.75a3 3 0 1 1-6 0 3 3 0 0 1 6 0Zm6 3a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Zm-13.5 0a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Z" />
      </svg>
    title: 天生面向多运行时
    details: 同一个 Dart 服务端项目可以交付到 Dart VM、Node.js、Bun、Deno、Cloudflare Workers、Vercel 与 Netlify，而不需要为每个平台重写路由代码。
  - icon: >-
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="size-6">
        <path stroke-linecap="round" stroke-linejoin="round" d="M6.429 9.75 2.25 12l4.179 2.25m0-4.5 5.571 3 5.571-3m-11.142 0L2.25 7.5 12 2.25l9.75 5.25-4.179 2.25m0 0L21.75 12l-4.179 2.25m0 0 4.179 2.25L12 21.75 2.25 16.5l4.179-2.25m11.142 0-5.571 3-5.571-3" />
      </svg>
    title: Oref 与务实基础能力
    details: 当你需要低侵入响应式、依赖注入或聚焦型应用工具时，再按需叠加 Oref、Oinject、Oncecall 与配套包。
  - icon: >-
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="size-6">
        <path stroke-linecap="round" stroke-linejoin="round" d="M9.813 15.904 9 18.75l-1.313-4.593a.75.75 0 0 0-1.036-.482l-2.75 1.179 1.353-3.086a.75.75 0 0 0-.104-.777L3 8.25l3.457.103a.75.75 0 0 0 .665-.34L9 5.25l1.878 2.763a.75.75 0 0 0 .665.34L15 8.25l-2.15 2.741a.75.75 0 0 0-.104.777l1.353 3.086-2.75-1.179a.75.75 0 0 0-1.036.482L9.813 15.904ZM18.25 8.25h3.5m-1.75-1.75v3.5m-1.75 8.25h3.5m-1.75-1.75v3.5" />
      </svg>
    title: 不靠黑盒的 AI 辅助开发体验
    details: 保持生成产物可检查，让 OpenAPI 与类型化客户端对齐，并为 AI 工具提供可推理的真实工件，而不是不透明的框架状态。
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
