<template>
  <NuxtLoadingIndicator :color="false" class="bg-black dark:bg-white" />
  <AppHeader />
  <NuxtPage />
</template>

<script lang="ts" setup>
const { seo } = useAppConfig();

useHead({
  titleTemplate: (title) =>
    title ? `${title} - ${seo.title}` : `${seo.title}: ${seo.slogan}`,
  link: [{ rel: 'icon', type: 'image/x-icon', href: '/favicon.ico' }],
});

useSeoMeta({
  description: seo.description,
  ogType: 'website',
  ogSiteName: seo.title,
  twitterSite: 'OdroeDev',
});
</script>

<style>
html,
body {
  @apply bg-white text-black dark:bg-black dark:text-white;
}
</style>
