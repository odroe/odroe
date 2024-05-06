<script lang="ts">
  import DocSidebar from './doc-sidebar.svelte';
  import { title } from 'radash';
  import type { PageData } from './$types';

  export let data: PageData;
</script>

<svelte:head>
  <title>
    Odroe → {title(data.current.category.title)}: {title(
      data.current.metadata.title ?? data.current.slug,
    )}
  </title>
  {#if data.current.metadata.description}
    <meta name="description" content={data.current.metadata.description} />
  {/if}
</svelte:head>

<DocSidebar pages={data.pages} current={data.current} />
<main class="pl-80 pt-6">
  <div class="text-sm leading-6 font-semibold text-indigo-500">
    {title(data.current.category.title)}
  </div>
  <div class="prose prose-indigo">{@html data.content}</div>
</main>
