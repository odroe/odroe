import { type DefaultTheme } from "vitepress";

const docsSidbar = [
  {
    text: "Introduction",
    collapsed: true,
    items: [{ text: "Getting Started", link: "/docs/getting-started" }],
  },
] satisfies DefaultTheme.SidebarItem[];

export default {
  "/docs/": docsSidbar,
} satisfies DefaultTheme.Sidebar;
