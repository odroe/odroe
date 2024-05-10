<template>
  <nav>
    <template v-for="link in navigation">
      <Menu as="div" class="relative" v-if="link.children?.length">
        <MenuButton
          class="nav-link flex items-center gap-1 group"
          :aria-selected="link.active"
        >
          {{ link.label }}
          <ChevronDownIcon
            class="size-4 transition-all group-aria-expanded:rotate-180"
          />
        </MenuButton>

        <transition
          enter-active-class="transition duration-100 ease-out"
          enter-from-class="transform scale-95 opacity-0"
          enter-to-class="transform scale-100 opacity-100"
          leave-active-class="transition duration-75 ease-in"
          leave-from-class="transform scale-100 opacity-100"
          leave-to-class="transform scale-95 opacity-0"
        >
          <MenuItems
            class="absolute mt-4 w-64 right-0 origin-top-right divide-y divide-gray-100 rounded-md bg-white ring-1 ring-black/5 focus:outline-none"
          >
            <div class="p-2 grid grid-cols-1 gap-2">
              <MenuItem v-for="child in link.children">
                <NuxtLink
                  :to="child.to"
                  :aria-selected="child.active"
                  class="p-2 pt-1 rounded flex gap-2 bg-transparent hover:bg-gray-100/75 aria-selected:bg-gray-100/75 transition-all"
                >
                  <component :is="child.icon" class="size-4 flex-none mt-1" />
                  <div class="flex-1 grow">
                    <h3 class="font-semibold text-sm/6 text-black">
                      {{ child.label }}
                    </h3>
                    <div class="line-clamp-2 text-sm/4 text-gray-600/75">
                      {{ child.desc }}
                    </div>
                  </div>
                </NuxtLink>
              </MenuItem>
            </div>
          </MenuItems>
        </transition>
      </Menu>

      <NuxtLink
        v-if="link.to"
        :to="link.to"
        :aria-selected="link.active"
        class="nav-link"
      >
        {{ link.label }}
      </NuxtLink>
    </template>
  </nav>
</template>

<script setup lang="ts">
import {
  Menu,
  MenuButton,
  MenuItem,
  MenuItems,
  provideUseId,
} from '@headlessui/vue';
import ChevronDownIcon from '@heroicons/vue/24/solid/ChevronDownIcon';

const navigation = useNavigation();

provideUseId(() => useId());
</script>

<style scoped>
.nav-link {
  @apply text-sm/6 font-semibold text-black dark:text-white relative before:absolute before:-left-4 before:-right-4 before:-top-1 before:-bottom-1 before:rounded-full before:bg-transparent before:hover:bg-black/5 aria-selected:before:bg-black/5 before:-z-10 dark:before:hover:bg-white/15 aria-selected:dark:before:bg-white/15;
}
</style>
