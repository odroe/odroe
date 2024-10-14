<script setup lang="ts">
import { computed } from "vue";
import { useData } from "vitepress";

type WhatIsNew = {
    name?: string;
    title?: string;
    link?: string;
};

const { frontmatter } = useData();
const whatIsNew = computed<WhatIsNew>(
    () => frontmatter.value.hero["what-is-new"] ?? {},
);
</script>

<template>
    <a
        v-if="whatIsNew.name || whatIsNew.title"
        :href="whatIsNew.link"
        class="group flex flex-row gap-4 mb-6 items-center"
    >
        <span
            class="border px-4 py-1 rounded-full border-green-400 bg-green-50 text-gray-900 font-medium text-sm dark:bg-green-500/10 dark:text-white"
        >
            {{ whatIsNew.name ?? "What's new" }}
        </span>
        <span
            v-if="whatIsNew.title"
            v-html="whatIsNew.title"
            class="text-sm text-gray-500 group-hover:text-gray-600 dark:text-gray-400 dark:group-hover:text-gray-300"
        ></span>
    </a>
</template>
