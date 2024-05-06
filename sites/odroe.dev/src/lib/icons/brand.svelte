<script lang="ts">
  import brandSource from '../assets/odroe-brand.svg?raw';

  type Props = {
    class?: string | null;
  };

  let { ...props }: Props = $props();

  const { 1: viewBox, 2: children } =
    /<svg.*?viewBox="(.*?)".*?>(.*?)<\/svg>/g.exec(
      brandSource
        .replace(/<defs.*?<\/defs>/gis, '')
        .replace(/\n\r?/g, ' ')
        .replace(/\s+/g, ' '),
    ) as unknown as {
      1: string;
      2: string;
    };
</script>

<svg xmlns="http://www.w3.org/2000/svg" {viewBox} {...props}>
  {@html children}
</svg>
