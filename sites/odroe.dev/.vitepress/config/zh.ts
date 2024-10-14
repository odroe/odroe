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
    nav: [{ text: "Packages", link: "/packages/" }],
    sidebar: [
      { text: "依赖注入", link: "/docs/oinject" },
      { text: "记忆化", link: "/docs/oncecall" },
    ],
    lastUpdatedText: "更新于",
  },
});
