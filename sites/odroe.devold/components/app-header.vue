<template>
  <header
    class="w-full h-16 sticky z-50 top-0 backdrop-blur bg-white/75 dark:bg-black/75"
  >
    <div
      class="mx-auto px-4 sm:px-6 lg:px-8 max-w-7xl flex items-center justify-between gap-3 h-full"
    >
      <NuxtLink to="/" class="lg:flex-1">
        <BrandLogo class="h-6 fill-black dark:fill-white" />
      </NuxtLink>

      <Navigation class="hidden lg:flex items-center gap-x-8" />

      <div class="flex-1 justify-end hidden lg:flex"></div>

      <MobileNavigation />
    </div>
  </header>
</template>
