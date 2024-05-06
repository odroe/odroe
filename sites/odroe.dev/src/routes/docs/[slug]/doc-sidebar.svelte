<script lang="ts">
  import { title, sort, unique } from 'radash';
  import type { Page } from '../../../lib/server/contents';
  import { resolveRoute } from '$app/paths';

  type Props = {
    pages: Page[];
    current: Page;
  };

  const { pages, current = $bindable() }: Props = $props();
  const resources = sort(
    unique(
      pages.map((p) => p.category),
      (p) => p.title,
    ),
    (p) => p.index,
  ).map((category) => {
    const children = pages
      .filter((p) => p.category.title == category.title)
      .map(({ category: _, type: __, ...page }) => page);

    return { ...category, pages: sort(children, (p) => p.index) };
  });
</script>

<aside class="fixed z-20 w-80 inset-0 mt-20 pl-6 overflow-x-hidden space-y-12">
  {#each resources as category}
    <div>
      <h5 class="font-semibold text-slate-900 mb-3 capitalize">
        {title(category.title)}
      </h5>
      <div class="space-y-2 border-l border-slate-100">
        {#each category.pages as { slug, metadata }}
          <a
            data-selected={slug == current.slug}
            href={resolveRoute('/docs/[slug]', { slug })}
            class="block border-l pl-4 -ml-px border-transparent text-sm hover:border-slate-400 text-slate-700 hover:text-slate-900 data-[selected=true]:text-indigo-600 data-[selected=true]:font-semibold data-[selected=true]:border-indigo-600"
          >
            {title(metadata.title ?? slug)}
          </a>
        {/each}
      </div>
    </div>
  {/each}
</aside>
