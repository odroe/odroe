import { type DefaultTheme, type HeadConfig, defineConfig } from 'vitepress';
import nav from './nav.config';

const app = {
  name: 'Odroe',
  slogan: 'Create user interfaces from Setup-widget',
  description:
    'Odroe is an declarative, efficient, and flexible Flutter UI framework for building user interfaces.',
};

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
  // 'pages/(.*)': '(.*)',
  // 'docs/index.md': 'docs.md',
} satisfies Record<string, string>;

const head = [
  ['link', { rel: 'icon', href: '/favicon.ico' }],
] satisfies HeadConfig[];

// https://vitepress.dev/reference/site-config
export default defineConfig({
  outDir: 'dist',
  title: app.name,
  titleTemplate: app.name,
  description: app.description,
  cleanUrls: true,
  head,
  rewrites,
  themeConfig: { nav, socialLinks },
});
