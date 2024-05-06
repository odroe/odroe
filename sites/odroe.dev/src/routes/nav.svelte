<script lang="ts">
  import { page } from '$app/stores';

  type Menu = {
    title: string;
    href: string;
  };

  const menu: Menu[] = [
    // { href: '/docs', title: 'Documentation' },
    // { href: '/templates', title: 'Templates' },
    // { href: '/blog', title: 'Blog' },
    // { href: '/about', title: 'About' },
  ];
</script>

<nav
  class="flex flex-1 items-center justify-end space-x-1 text-base leading-6 font-medium"
>
  {#each menu as { href, title }}
    <a
      class="nav-item"
      {href}
      data-selected={$page.url.pathname.startsWith(href)}
    >
      {title}
    </a>
  {/each}
</nav>

<style lang="postcss">
  .nav-item {
    @apply text-black px-4 py-1.5 rounded-full capitalize transition-all duration-150;
    @apply hover:bg-gray-100 hover:-translate-y-0.5;
    @apply data-[selected="true"]:bg-indigo-50 data-[selected="true"]:text-indigo-600;
    @apply data-[selected="true"]:hover:translate-y-0;
  }
</style>
