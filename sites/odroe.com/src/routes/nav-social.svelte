<script lang="ts">
  import DiscordIcon from '$lib/icons/discord-icon.svelte';
  import GithubIcon from '$lib/icons/github-icon.svelte';
  import MinusIcon from '$lib/icons/minus-icon.svelte';
  import XIcon from '$lib/icons/x(twitter)-icon.svelte';
</script>

<MinusIcon class="h-8  origin-center rotate-90 stroke-1  stroke-zinc-200" />

<div class="flex items-center space-x-2">
  <a
    href="http://github.com/odroe/odroe"
    target="_blank"
    rel="noopener noreferrer"
  >
    <GithubIcon class="stroke-black size-6" />
    <span class="sr-only">View Odroe at GitHub</span>
  </a>

  <a
    href="https://twitter.com/OdroeDev"
    target="_blank"
    rel="noopener noreferrer"
  >
    <XIcon class="stroke-black h-5 w-6" />
    <span class="sr-only">Follow Odroe on X</span>
  </a>

  <a
    href="https://discord.gg/ms2X9TQMR8"
    target="_blank"
    rel="noopener noreferrer"
  >
    <DiscordIcon class="fill-black size-6" />
    <span class="sr-only">Join the Discord community of Odroe</span>
  </a>
</div>
