import { defineConfig } from "vitepress";

export default defineConfig({
  lang: "zh-Hans",
  description:
    "为 Dart 和 Flutter 应用程序中的反应式编程和依赖注入以及各种实用程序和工具。",
  head: [
    [
      "meta",
      {
        property: "og:title",
        content:
          "Odroe | 为 Dart 和 Flutter 应用程序中的反应式编程和依赖注入以及各种实用程序和工具。",
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
