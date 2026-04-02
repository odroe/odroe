---
title: Odroe 现阶段仅保留官网入口。
layout: home
hero:
  name: Odroe 现阶段仅保留官网入口。
  tagline: 这个站点继续作为 Odroe 的公开入口保留。历史上的 Dart / Flutter packages、实验项目与生态叙事已转为归档视角，不再属于活跃维护范围。
  image:
    light: /hero-light.png
    dark: /hero-dark.png
  actions:
    - theme: brand
      text: 访问 GitHub
      link: https://github.com/odroe
    - theme: alt
      text: 关注 X
      link: https://x.com/OdroeDev
  what-is-new:
    title: 范围更新：只有官网资产仍然活跃维护；历史 packages 与实验仓库仅保留为背景信息。
    link: https://github.com/odroe
features:
  - icon: >-
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="size-6">
        <path stroke-linecap="round" stroke-linejoin="round" d="m21 7.5-9-5.25L3 7.5m18 0-9 5.25m9-5.25v9l-9 5.25M3 7.5l9 5.25M3 7.5v9l9 5.25m0-9v9" />
      </svg>
    title: 仅保留官网范围
    details: Odroe 现在只保留官网、组织资料与维持这些公开入口准确所必需的最小资产。
  - icon: >-
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="size-6">
        <path stroke-linecap="round" stroke-linejoin="round" d="M18 18.72a9.094 9.094 0 0 0 3.741-.479 3 3 0 0 0-4.682-2.72m.94 3.198.001.031c0 .225-.012.447-.037.666A11.944 11.944 0 0 1 12 21c-2.17 0-4.207-.576-5.963-1.584A6.062 6.062 0 0 1 6 18.719m12 0a5.971 5.971 0 0 0-.941-3.197m0 0A5.995 5.995 0 0 0 12 12.75a5.995 5.995 0 0 0-5.058 2.772m0 0a3 3 0 0 0-4.681 2.72 8.986 8.986 0 0 0 3.74.477m.94-3.197a5.971 5.971 0 0 0-.94 3.197M15 6.75a3 3 0 1 1-6 0 3 3 0 0 1 6 0Zm6 3a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Zm-13.5 0a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Z" />
      </svg>
    title: 历史 packages 不再作为活跃产品
    details: 旧的 packages 页面、实验项目与 monorepo 代码不再对外宣传为活跃产品；除非未来明确重启，否则一律按归档材料看待。
  - icon: >-
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="size-6">
        <path stroke-linecap="round" stroke-linejoin="round" d="M6.429 9.75 2.25 12l4.179 2.25m0-4.5 5.571 3 5.571-3m-11.142 0L2.25 7.5 12 2.25l9.75 5.25-4.179 2.25m0 0L21.75 12l-4.179 2.25m0 0 4.179 2.25L12 21.75 2.25 16.5l4.179-2.25m11.142 0-5.571 3-5.571-3" />
      </svg>
    title: 降低维护面
    details: 缩小公开维护面，才能让 CCO 的长期动作停留在真实可维护边界内，而不是继续为已经废弃的仓库背书。
  - icon: >-
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="size-6">
        <path stroke-linecap="round" stroke-linejoin="round" d="M9.813 15.904 9 18.75l-1.313-4.593a.75.75 0 0 0-1.036-.482l-2.75 1.179 1.353-3.086a.75.75 0 0 0-.104-.777L3 8.25l3.457.103a.75.75 0 0 0 .665-.34L9 5.25l1.878 2.763a.75.75 0 0 0 .665.34L15 8.25l-2.15 2.741a.75.75 0 0 0-.104.777l1.353 3.086-2.75-1.179a.75.75 0 0 0-1.036.482L9.813 15.904ZM18.25 8.25h3.5m-1.75-1.75v3.5m-1.75 8.25h3.5m-1.75-1.75v3.5" />
      </svg>
    title: 对外预期更清晰
    details: 官网应该直接说明什么仍在维护、什么只是历史遗留，避免让外部继续把废弃项目理解成当前承诺。
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
    公开入口
  </template>
  <template #lead>
    官网继续保留，作为 Odroe 组织最小但准确的公开入口。
  </template>
</VPTeamPageTitle>

<a href="https://github.com/odroe/odroe/graphs/contributors" >
  <img src="https://contrib.rocks/image?repo=odroe/odroe" class="mx-auto" />
</a>
