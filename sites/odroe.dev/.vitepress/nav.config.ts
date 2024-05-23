import { type DefaultTheme } from "vitepress";

const docs = {
  text: "Docs",
  link: "/docs/getting-started",
  // items: [
  //   { text: "Get Started", link: "/docs/getting-started" },
  //   // { text: "Guide", link: "/docs/guide" },
  //   // { text: "API", link: "/docs/api" },
  //   // { text: "Examples", link: "/docs/examples" },
  //   // { text: "Community", link: "/docs/community" },
  // ],
} satisfies DefaultTheme.NavItem;

const ui = {
  text: "UI",
  link: "/ui",
} satisfies DefaultTheme.NavItem;

const templates = {
  text: "Templates",
  link: "/templates",
} satisfies DefaultTheme.NavItem;

const showcase = {
  text: "Showcase",
  link: "/showcase",
} satisfies DefaultTheme.NavItem;

const enterprise = {
  text: "Enterprise",
  items: [
    // { text: "Support", link: "/enterprise/support" },
    // { text: "Sponsors", link: "/enterprise/sponsors" },
    {
      text: "Sponsors",
      link: "https://github.com/sponsors/medz",
    },
  ],
} satisfies DefaultTheme.NavItem;

const blog = { text: "Blog", link: "/blog" } satisfies DefaultTheme.NavItem;

export default [
  docs,
  // ui,
  // templates,
  // showcase,
  enterprise,
  // blog,
] satisfies DefaultTheme.NavItem[];
