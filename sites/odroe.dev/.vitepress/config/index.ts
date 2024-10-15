import { defineConfig } from "vitepress";
import en from "./en";
import zh from "./zh";

export default defineConfig({
  title: "Odroe",
  titleTemplate: "Odroe | :title",

  cleanUrls: true,
  metaChunk: true,
  lastUpdated: true,

  rewrites: {
    "en/:rest*": ":rest*",
  },

  sitemap: {
    hostname: "https://odroe.dev",
  },

  head: [
    ["link", { rel: "icon", type: "image/svg+xml", href: "/favicon.svg" }],
    ["link", { rel: "icon", type: "image/png", href: "/favicon.png" }],
    ["meta", { name: "theme-color", content: "#000000" }],
    ["meta", { property: "og:type", content: "website" }],
    ["meta", { property: "og:site_name", content: "Odroe" }],
    ["meta", { property: "og:url", content: "https://odroe.dev/" }],
    [
      "meta",
      { property: "og:image", content: "https://odroe.dev/social-preview.png" },
    ],
  ],

  themeConfig: {
    siteTitle: false,
    logo: {
      light: "/brand-light.svg",
      dark: "/brand-dark.svg",
    },

    socialLinks: [
      { icon: "github", link: "https://github.com/odroe/odroe" },
      { icon: "x", link: "https://x.com/shiweidu" },
      { icon: "discord", link: "https://odroe.dev/chat" },
    ],
  },

  locales: {
    root: { label: "English", ...en },
    zh: { label: "简体中文", ...zh },
  },
});
