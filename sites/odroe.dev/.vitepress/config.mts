import { type DefaultTheme, type HeadConfig, defineConfig } from 'vitepress';
import navConfig from './nav.config';
import sidebarConfig from './sidebar.config';
import editLinkConfig from './edit-link.config';
import appData from '../app.data';

const app = appData.load();

const socialLinks = [
  {
    icon: 'github',
    link: 'https://github.com/odroe/odroe',
  },
  {
    icon: 'x',
    link: 'https://x.com/odroedev',
  },
  // {
  //   icon: 'discord',
  //   link: 'https://odroe.dev/chat',
  // },
] satisfies DefaultTheme.SocialLink[];

const rewrites = {
  'docs/ui.md': 'ui.md',
  'docs/ui/(.*)': 'ui/(.*).md',
  // 'docs/index.md': 'docs.md',
} satisfies Record<string, string>;

const head = [
  ['link', { rel: 'icon', href: '/favicon.ico' }],
] satisfies HeadConfig[];

const logo = {
  light: '/brand-light.svg',
  dark: '/brand-dark.svg',
} satisfies DefaultTheme.ThemeableImage;

// https://vitepress.dev/reference/site-config
export default defineConfig({
  outDir: 'dist',
  title: `${app.name}: ${app.slogan}`,
  titleTemplate: `${app.name} → :title`,
  description: app.description,
  cleanUrls: true,
  head,
  rewrites,
  lastUpdated: true,
  themeConfig: {
    nav: navConfig,
    sidebar: sidebarConfig,
    socialLinks,
    logo,
    siteTitle: false,
    editLink: editLinkConfig,
  },
});
