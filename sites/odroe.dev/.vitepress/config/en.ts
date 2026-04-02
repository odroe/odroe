import { defineConfig } from "vitepress";

export default defineConfig({
  lang: "en-US",
  description:
    "Odroe is now maintained as a website-only public entry. Historical packages and experiments are archived and no longer actively maintained.",
  head: [
    [
      "meta",
      {
        property: "og:title",
        content:
          "Odroe | Website-only public entry",
      },
    ],
  ],

  themeConfig: {
    nav: [],
    sidebar: [],
  },
});
