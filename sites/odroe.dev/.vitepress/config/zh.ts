import { defineConfig } from "vitepress";

export default defineConfig({
  lang: "zh-Hans",
  description:
    "以 Spry 为先的 Dart 基础设施，聚焦文件路由服务端、多运行时交付与务实的 AI 辅助开发体验。",
  head: [
    [
      "meta",
      {
        property: "og:title",
        content:
          "Odroe | 面向多运行时交付的 Spry 优先 Dart 基础设施。",
      },
    ],
  ],

  themeConfig: {
    nav: [{ text: "Packages", link: "/zh/packages/" }],
    sidebar: [
      { text: "依赖注入", link: "/zh/docs/oinject" },
      { text: "记忆化", link: "/zh/docs/oncecall" },
      {
        text: "响应式",
        items: [
          { text: "介绍", link: "/zh/docs/oref/introduction" },
          { text: "快速开始", link: "/zh/docs/oref/get-started" },
          { text: "核心", link: "/zh/docs/oref/core" },
          { text: "工具", link: "/zh/docs/oref/utils" },
          { text: "进阶", link: "/zh/docs/oref/advanced" },
        ],
      },
    ],
    lastUpdatedText: "更新于",
  },
});
