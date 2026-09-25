// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

const reference = (version) => ({
  label: 'API reference',
  items: ['network', 'state-replication', 'component-service', 'state-machine', 'module-loader', 'player-lifecycle', 'utilities'].map((name) => ({
    label: name.split('-').map((word) => word[0].toUpperCase() + word.slice(1)).join(' '),
    slug: `versions/${version}/api/${name}`,
  })),
});

const detailedVersion = (version, label) => ({
  label,
  collapsed: true,
  items: [
    { label: 'Overview', slug: `versions/${version}` },
    { label: 'Learn', items: [
      { label: 'Getting started', slug: `versions/${version}/guides/getting-started` },
      { label: 'Project structure', slug: `versions/${version}/guides/project-structure` },
      { label: 'Module lifecycle', slug: `versions/${version}/guides/module-lifecycle` },
    ] },
    reference(version),
  ],
});

const legacyVersion = (version) => ({
  label: version,
  collapsed: true,
  items: [
    { label: 'Overview', slug: `versions/${version}` },
    { label: 'Learn', items: [
      { label: 'Getting started', slug: `versions/${version}/guides/getting-started` },
      { label: 'Module lifecycle', slug: `versions/${version}/guides/module-lifecycle` },
    ] },
    { label: 'API reference', items: [
      { label: 'Networking', slug: `versions/${version}/api/network` },
      { label: 'Tagged components', slug: `versions/${version}/api/component-service` },
      ...(['0.7.0', '0.7.1'].includes(version) ? [{ label: 'State replication', slug: `versions/${version}/api/state-replication` }] : []),
    ] },
    { label: 'Historical release guide', slug: `versions/${version}/readme` },
  ],
});

const maelstrom = detailedVersion('0.9.0-maelstrom.3', 'Preview · Maelstrom-3');
const legacyRoutes = [
  ...['getting-started', 'module-lifecycle', 'plugins', 'project-structure'].map((name) => `guides/${name}`),
  ...['component-service', 'module-loader', 'network', 'player-lifecycle', 'state-machine', 'state-replication', 'utilities'].map((name) => `api/${name}`),
  ...['framework-plugin', 'server-service', 'typed-network-state'].map((name) => `examples/${name}`),
  ...['from-0-8-2', 'from-maelstrom-2'].map((name) => `migration/${name}`),
];
const stable = detailedVersion('0.8.2', 'Latest stable · 0.8.2');
stable.items[1].items.unshift(
  { label: 'Your first 10 minutes', slug: 'versions/0.8.2/guides/quickstart' },
  { label: 'Learning path', slug: 'versions/0.8.2/guides/learning-path' },
);
stable.items.push({ label: 'Examples', items: [
  { label: 'Player coins', slug: 'versions/0.8.2/examples/player-coins' },
] });
maelstrom.items[1].items.push(
  { label: 'Plugins', slug: 'versions/0.9.0-maelstrom.3/guides/plugins' },
);
maelstrom.items.push(
  { label: 'Examples', items: [
    { label: 'Server service', slug: 'versions/0.9.0-maelstrom.3/examples/server-service' },
    { label: 'Typed network and state', slug: 'versions/0.9.0-maelstrom.3/examples/typed-network-state' },
    { label: 'Framework plugin', slug: 'versions/0.9.0-maelstrom.3/examples/framework-plugin' },
  ] },
  { label: 'Migration', items: [
    { label: 'From 0.8.2', slug: 'versions/0.9.0-maelstrom.3/migration/from-0-8-2' },
    { label: 'From Maelstrom-2', slug: 'versions/0.9.0-maelstrom.3/migration/from-maelstrom-2' },
  ] },
);

export default defineConfig({
  site: 'https://riptide-project.github.io/framework/',
  base: '/framework/',
  trailingSlash: 'always',
  redirects: Object.fromEntries(legacyRoutes.map((route) => [
    `/${route}/`, `/framework/versions/0.9.0-maelstrom.3/${route}/`,
  ])),
  integrations: [
    starlight({
      title: 'Riptide',
      logo: { src: './src/assets/logo.svg', alt: 'Riptide' },
      favicon: 'favicon.svg',
      pagination: false,
      customCss: ['./src/styles/custom.css'],
      components: { Header: './src/components/Header.astro' },
      social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/riptide-project/framework' }],
      sidebar: [
        { label: 'Start here', items: [
          { label: 'Riptide overview', slug: '' },
          { label: 'Your first 10 minutes', slug: 'versions/0.8.2/guides/quickstart' },
          { label: 'All versions', slug: 'versions' },
        ] },
        stable,
        maelstrom,
        detailedVersion('0.9.0-maelstrom.2', 'Earlier preview · Maelstrom-2'),
        { label: 'Earlier stable releases', collapsed: true, items: [
          detailedVersion('0.8.1', '0.8.1'),
          detailedVersion('0.8.0', '0.8.0'),
          ...['0.7.1', '0.7.0', '0.6.0', '0.5.0', '0.4.0', '0.3.0'].map(legacyVersion),
        ] },
      ],
    }),
  ],
});
