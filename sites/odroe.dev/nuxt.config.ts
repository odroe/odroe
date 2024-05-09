import { fileURLToPath } from 'url';

// https://nuxt.com/docs/api/configuration/nuxt-config
export default defineNuxtConfig({
  devtools: { enabled: true },
  modules: ['@nuxt/content'],
  content: {
    sources: {
      content: {
        driver: 'fs',
        prefix: '/docs',
        base: fileURLToPath(new URL('../../docs', import.meta.url)),
      },
    },
  },
});
