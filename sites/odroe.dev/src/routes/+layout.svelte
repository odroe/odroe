<script lang="ts">
  import Brand from '$lib/icons/brand.svelte';
  import NavSocial from './nav-social.svelte';
  import Nav from './nav.svelte';
  import Search from './search.svelte';
</script>

<svelte:head>
  <title>Odroe: Create user interfaces from Setup-widget</title>
  <meta
    name="description"
    content="A declarative, efficient, and flexible Flutter UI framework for building user interfaces."
  />
</svelte:head>

<header class="w-full h-14 sticky px-6 flex items-center z-50 top-0">
  <a href="/" class="inline-flex space-x-2 items-center" title="Odroe">
    <Brand class="aspect-square h-8 fill-indigo-500" />
    <span class="sr-only">Goto Odroe homepage</span>
    <span class="capitalize text-lg font-semibold">Odroe</span>
  </a>
  <!-- <div class="px-8">
    <Search />
  </div> -->
  <Nav />
  <NavSocial />
</header>

<slot />
