<script setup lang="ts">
import DefaultTheme from "vitepress/theme";
import WhatIsNew from "./components/what-is-new.vue";

const { Layout } = DefaultTheme;
</script>

<template>
    <Layout>
        <template #home-hero-info-before>
            <WhatIsNew />
        </template>
    </Layout>
</template>
