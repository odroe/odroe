<template>
  <div class="tw-backdrop-blur">
    <VPNavBar
      :is-screen-open="isScreenOpen"
      @toggle-screen="$emit('toggle-screen')"
    >
    </VPNavBar>
  </div>
</template>

<script setup lang="ts">
import VPNavBar from '../default-theme/vitepress-navbar.vue';

defineProps<{
  isScreenOpen: boolean;
}>();

defineEmits<{
  (e: 'toggle-screen'): void;
}>();
</script>
