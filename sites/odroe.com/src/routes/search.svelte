<script lang="ts">
  import SearchIcon from '$lib/icons/search-icon.svelte';
</script>

<button
  type="button"
  class="text-left bg-gray-100 text-zinc-500 rounded-full px-4 py-2 flex items-center font-light"
>
  <span class="flex items-center space-x-2">
    <SearchIcon class="size-5 stroke-2" />
    <span class="capitalize">Search</span>
  </span>
  <span class="ml-6 text-sm border border-zinc-400 rounded px-2 h-5 leading-5">
    <kbd class="h-6 leading-5">⌘</kbd>
    <kbd class="h-6 leading-5">K</kbd>
  </span>
</button>
