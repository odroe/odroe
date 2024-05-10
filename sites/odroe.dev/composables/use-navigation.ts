import { createSharedComposable } from '@vueuse/core';
import SparklesIcon from '@heroicons/vue/24/outline/SparklesIcon';
import HeartIcon from '@heroicons/vue/24/outline/HeartIcon';

export const useNavigation = createSharedComposable(() =>
  computed(() => {
    const route = useRoute();

    return [
      { label: 'Docs', to: '/docs', active: route.path.startsWith('/docs') },
      { label: 'UI', to: '/ui', active: route.path.startsWith('/ui') },
      {
        label: 'Templates',
        to: '/templates',
        active: route.path.startsWith('/templates'),
      },
      {
        label: 'Showcase',
        to: '/showcase',
        active: route.path.startsWith('/showcase'),
      },
      {
        label: 'Enterprise',
        active: route.path.startsWith('/enterprise'),
        children: [
          {
            label: 'Support',
            to: '/enterprise/support',
            active: route.path.startsWith('/enterprise/support'),
            desc: 'Get help with Odroe directly from the team that creates it.',
            icon: SparklesIcon,
          },
          {
            label: 'Sponsors',
            to: '/enterprise/support',
            active: route.path.startsWith('/enterprise/sponsors'),
            desc: 'Become a sponsor and get your logo on our README on GitHub with a link to your site.',
            icon: HeartIcon,
          },
        ],
      },
      { label: 'Blog', to: '/blog', active: route.path.startsWith('/blog') },
    ];
  }),
);
