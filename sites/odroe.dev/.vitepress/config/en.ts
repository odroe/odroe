import { defineConfig } from "vitepress";

export default defineConfig({
  lang: "en-US",
  description:
    "For reactive programming and dependency injection in Dart and Flutter applications, as well as various utilities and tools.",
  head: [
    [
      "meta",
      {
        property: "og:title",
        content:
          "Odroe | For reactive programming and dependency injection in Dart and Flutter applications, as well as various utilities and tools.",
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
