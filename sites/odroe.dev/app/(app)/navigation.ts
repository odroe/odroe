import SparklesIcon from '@heroicons/react/24/outline/SparklesIcon';
import HeartIcon from '@heroicons/react/24/outline/HeartIcon';

export const navigation = [
  { label: 'Docs', href: '/docs' },
  { label: 'UI', href: '/ui' },
  { label: 'Templates', href: '/templates' },
  { label: 'Showcase', href: '/showcase' },
  {
    label: 'Enterprise',
    href: '/enterprise',
    children: [
      {
        label: 'Support',
        href: '/enterprise/support',
        desc: 'Get help with Odroe directly from the team that creates it.',
        icon: SparklesIcon,
      },
      {
        label: 'Sponsors',
        href: '/enterprise/sponsors',
        desc: 'Become a sponsor and get your logo on our README on GitHub with a link to your site.',
        icon: HeartIcon,
      },
    ],
  },
  { label: 'Blog', href: '/blog' },
];
