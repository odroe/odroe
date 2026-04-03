import { defineConfig } from "vitepress";

export default defineConfig({
  lang: "en-US",
  description:
    "Odroe is the public brand and project entry behind practical open source tools, experiments, and developer-facing work from Seven Du.",
  head: [
    [
      "meta",
      {
        property: "og:title",
        content:
          "Odroe | Open source brand and project entry",
      },
    ],
  ],

  themeConfig: {
    nav: [
      { text: "Home", link: "/" },
      { text: "Projects", link: "/packages/" },
      { text: "GitHub", link: "https://github.com/odroe" },
      { text: "Medium", link: "https://shiwei.medium.com/" },
    ],
    sidebar: [],
  },
});
