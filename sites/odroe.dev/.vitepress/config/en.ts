import { defineConfig } from "vitepress";

export default defineConfig({
  lang: "en-US",
  description:
    "Spry-first Dart infrastructure for file-routed servers, cross-runtime deployment, and practical AI-assisted DX.",
  head: [
    [
      "meta",
      {
        property: "og:title",
        content:
          "Odroe | Spry-first Dart infrastructure across runtimes.",
      },
    ],
  ],

  themeConfig: {
    nav: [{ text: "Packages", link: "/packages/" }],
    sidebar: [
      { text: "Dependency Injection", link: "/docs/oinject" },
      { text: "Memoization", link: "/docs/oncecall" },
      {
        text: "Reactive",
        items: [
          { text: "Introduction", link: "/docs/oref/introduction" },
          { text: "Getting Started", link: "/docs/oref/get-started" },
          { text: "Core", link: "/docs/oref/core" },
          { text: "Utilities", link: "/docs/oref/utils" },
          { text: "Advanced", link: "/docs/oref/advanced" },
        ],
      },
    ],
  },
});
