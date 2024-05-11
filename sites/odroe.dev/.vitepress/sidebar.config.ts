import { type DefaultTheme } from 'vitepress';

const docsSidbar = [
  {
    text: 'Get Started',
    collapsed: true,
    items: [
      { text: 'Introduction', link: '/docs/getting-started/introduction' },
      { text: 'Installation', link: '/docs/getting-started/installation' },
    ],
  },
] satisfies DefaultTheme.SidebarItem[];

export default {
  '/docs/': docsSidbar,
} satisfies DefaultTheme.Sidebar;
