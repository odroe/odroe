import { defineConfig } from "vitepress";

export default defineConfig({
  lang: "zh-Hans",
  description:
    "Odroe 是 Seven Du 面向外部的品牌与项目入口，用来承接开源工具、实验项目和开发者产品方向。",
  head: [
    [
      "meta",
      {
        property: "og:title",
        content:
          "Odroe | 开源品牌与项目入口",
      },
    ],
  ],

  themeConfig: {
    nav: [
      { text: "首页", link: "/zh/" },
      { text: "项目", link: "/zh/packages/" },
      { text: "GitHub", link: "https://github.com/odroe" },
      { text: "Medium", link: "https://shiwei.medium.com/" },
    ],
    sidebar: [],
    lastUpdatedText: "更新于",
  },
});
