import { defineConfig } from "vitepress";

export default defineConfig({
  lang: "zh-Hans",
  description:
    "Odroe 现阶段只保留官网入口。历史 packages 与实验项目已转为归档视角，不再作为持续维护对象。",
  head: [
    [
      "meta",
      {
        property: "og:title",
        content:
          "Odroe | 仅保留官网入口",
      },
    ],
  ],

  themeConfig: {
    nav: [],
    sidebar: [],
    lastUpdatedText: "更新于",
  },
});
