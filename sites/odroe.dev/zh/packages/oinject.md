---
title: Oinject 参考文档与 Flutter 依赖注入说明
description: Oinject 继续保留在 odroe.dev 上，作为 Flutter 依赖注入模式的参考文档页，但不再被包装成当前主推项目入口。
head:
  - - meta
    - property: og:title
      content: Odroe | Oinject 参考文档与 Flutter 依赖注入说明
layout: home
hero:
  name: Oinject 参考文档
  tagline: Oinject 继续保留在这里，作为 Flutter 依赖注入模式的参考资料；Odroe 当前更应该从项目总入口去理解正在公开推进的方向。
  actions:
    - theme: brand
      text: 阅读参考文档 →
      link: /zh/docs/oinject.md
    - theme: alt
      text: 浏览当前项目
      link: /zh/packages/
    - theme: alt
      text: 在 pub.dev 查看
      link: https://pub.dev/packages/oinject
features:
  - icon: >-
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="size-6">
        <path stroke-linecap="round" stroke-linejoin="round" d="M17.25 6.75 22.5 12l-5.25 5.25m-10.5 0L1.5 12l5.25-5.25m7.5-3-4.5 16.5" />
      </svg>
    title: 参考包文档
    details: 这个页面继续保留 Oinject 的文档、示例与包信息，方便仍在使用它的团队快速查阅。
  - icon: >-
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="size-6">
        <path stroke-linecap="round" stroke-linejoin="round" d="M9.348 14.652a3.75 3.75 0 0 1 0-5.304m5.304 0a3.75 3.75 0 0 1 0 5.304m-7.425 2.121a6.75 6.75 0 0 1 0-9.546m9.546 0a6.75 6.75 0 0 1 0 9.546M5.106 18.894c-3.808-3.807-3.808-9.98 0-13.788m13.788 0c3.808 3.807 3.808 9.98 0 13.788M12 12h.008v.008H12V12Zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0Z" />
      </svg>
    title: 自动追踪
    details: 祖先组件注入值触发更新时，会自动探测后代使用情况，减少不必要的重建。
  - icon: >-
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="size-6">
        <path stroke-linecap="round" stroke-linejoin="round" d="M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375m16.5 0v3.75m-16.5-3.75v3.75m16.5 0v3.75C20.25 16.153 16.556 18 12 18s-8.25-1.847-8.25-4.125v-3.75m16.5 0c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125" />
      </svg>
    title: 数据堆叠
    details: 可以覆盖上层数据而不产生额外副作用，也能按不同类型使用统一 Key 进行数据堆叠。
---

## 参考状态

- Oinject 继续保留在 odroe.dev 上，定位是参考文档，而不是当前旗舰项目入口。
- 如果你想先看 Odroe 现在重点推进的项目，请先从 [/zh/packages/](/zh/packages/) 开始。
- 如果你已经在使用 Oinject，这里的文档和包链接仍然是继续查阅的最快入口。
