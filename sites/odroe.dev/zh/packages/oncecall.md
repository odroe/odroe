---
title: Oncecall
description: Oncecall 继续保留在 odroe.dev 上，作为 Flutter Widget.build 记忆化模式的参考文档页。
head:
  - - meta
    - property: og:title
      content: Odroe | Oncecall 参考文档与 Flutter Widget.build 记忆化说明
layout: home
hero:
  name: Oncecall 参考文档
  tagline: Oncecall 继续保留在这里，作为 Flutter Widget.build 记忆化模式的参考资料；Odroe 当前更应该从项目总入口去理解正在公开推进的方向。
  actions:
    - theme: brand
      text: 阅读参考文档 →
      link: /zh/docs/oncecall.md
    - theme: alt
      text: 浏览当前项目
      link: /zh/packages/
    - theme: alt
      text: 在 pub.dev 查看
      link: https://pub.dev/packages/oncecall
features:
  - icon: >-
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="size-6">
        <path stroke-linecap="round" stroke-linejoin="round" d="m21 7.5-2.25-1.313M21 7.5v2.25m0-2.25-2.25 1.313M3 7.5l2.25-1.313M3 7.5l2.25 1.313M3 7.5v2.25m9 3 2.25-1.313M12 12.75l-2.25-1.313M12 12.75V15m0 6.75 2.25-1.313M12 21.75V19.5m0 2.25-2.25-1.313m0-16.875L12 2.25l2.25 1.313M21 14.25v2.25l-2.25 1.313m-13.5 0L3 16.5v-2.25" />
      </svg>
    title: 参考包文档
    details: 这个页面继续保留 Oncecall 的文档、示例与包信息，方便仍在使用它的团队快速查阅。
  - icon: >-
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="size-6">
        <path stroke-linecap="round" stroke-linejoin="round" d="M21 12a2.25 2.25 0 0 0-2.25-2.25H15a3 3 0 1 1-6 0H5.25A2.25 2.25 0 0 0 3 12m18 0v6a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 18v-6m18 0V9M3 12V9m18 0a2.25 2.25 0 0 0-2.25-2.25H5.25A2.25 2.25 0 0 0 3 9m18 0V6a2.25 2.25 0 0 0-2.25-2.25H5.25A2.25 2.25 0 0 0 3 6v3" />
      </svg>
    title: 记忆化
    details: 按照调用顺序自动记忆计算值，并在 Widget 重建时继续复用。
  - icon: >-
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="size-6">
        <path stroke-linecap="round" stroke-linejoin="round" d="M9.813 15.904 9 18.75l-.813-2.846a4.5 4.5 0 0 0-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 0 0 3.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 0 0 3.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 0 0-3.09 3.09ZM18.259 8.715 18 9.75l-.259-1.035a3.375 3.375 0 0 0-2.455-2.456L14.25 6l1.036-.259a3.375 3.375 0 0 0 2.455-2.456L18 2.25l.259 1.035a3.375 3.375 0 0 0 2.456 2.456L21.75 6l-1.035.259a3.375 3.375 0 0 0-2.456 2.456ZM16.894 20.567 16.5 21.75l-.394-1.183a2.25 2.25 0 0 0-1.423-1.423L13.5 18.75l1.183-.394a2.25 2.25 0 0 0 1.423-1.423l.394-1.183.394 1.183a2.25 2.25 0 0 0 1.423 1.423l1.183.394-1.183.394a2.25 2.25 0 0 0-1.423 1.423Z" />
      </svg>
    title: 生命周期作用域
    details: 当 Widget 被销毁后，记忆内容也会一起消失，不会保留污染数据。
---

## 参考状态

- Oncecall 继续保留在 odroe.dev 上，定位是参考文档，而不是当前旗舰项目入口。
- 如果你想先看 Odroe 现在重点推进的项目，请先从 [/zh/packages/](/zh/packages/) 开始。
- 如果你已经在使用 Oncecall，这里的文档和包链接仍然是继续查阅的最快入口。
