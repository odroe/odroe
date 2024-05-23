---
layout: home
title: "Odroe: Create user interfaces from Setup-widget"
titleTemplate: false
hero:
  text: Create user interfaces from Setup-widget
  tagline: A declarative, efficient, and flexible Flutter UI framework for building user interfaces.
  actions:
    - theme: brand
      text: </> Get Started
      link: /docs/getting-started
    - theme: alt
      text: What is Odroe?
      link: /docs/getting-started
features:
  - title: Refined
    details: the amount of code is significantly reduced compared to Class Widget.
  - title: Conciseness
    details: Less code compared to class-widgets.
  - title: Compositional
    details: Setup-widgets are typical functional widgets, encouraging the learning of powerful composition, reusability, and construction concepts.
---

<script setup>
import { VPTeamMembers } from 'vitepress/theme';

const members = [
  {
    avatar: 'https://www.github.com/medz.png',
    name: 'Seven Du',
    title: 'Coder · Designer · Creator',
    org: "Odroe",
    orgLink: "https://github.com/odroe",
    sponsor: "https://github.com/sponsors/medz",
    links: [
      { icon: 'github', link: 'https://github.com/medz' },
      { icon: 'twitter', link: 'https://twitter.com/shiweidu' }
    ]
  },
  {
    avatar: 'https://www.github.com/skillLan.png',
    name: 'Skill Lan',
    org: "Odroe",
    orgLink: "https://github.com/odroe",
    title: 'Account Manager · IOS Engineer',
    links: [
      { icon: 'github', link: 'https://github.com/skillLan' },
    ]
  },
];
</script>

<h1 class="tw-text-center tw-mt-12">Meet Our Team</h1>

<p class="tw-text-center">We’re a dynamic group of individuals who are passionate about what we do.</p>

<VPTeamMembers size="small" :members="members" />
