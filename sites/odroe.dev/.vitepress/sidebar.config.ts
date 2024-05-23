import { type DefaultTheme } from "vitepress";

const docsSidbar = [
  {
    text: "Introduction",
    collapsed: false,
    items: [
      { text: "What's Odroe?", link: "/docs/what-is-odroe" },
      { text: "Getting Started", link: "/docs/getting-started" },
    ],
  },
  {
    text: "Essentials",
    collapsed: false,
    items: [
      { text: "Functional Widget", link: "/docs/essentials/functional-widget" },
      { text: "Signals", link: "/docs/essentials/signals" },
      { text: "Lifecycle", link: "/docs/essentials/lifecycle" },
      { text: "Composables", link: "/docs/essentials/composables" },
    ],
  },
] satisfies DefaultTheme.SidebarItem[];

export default {
  "/docs/": docsSidbar,
} satisfies DefaultTheme.Sidebar;
