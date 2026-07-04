// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// https://astro.build/config
export default defineConfig({
	site: 'https://riptide-project.github.io/framework/',
	base: '/framework/',
	trailingSlash: 'always',
	integrations: [
		starlight({
			title: 'Riptide Framework',
			logo: {
				src: './src/assets/logo.png',
			},
			favicon: 'favicon.png',
			customCss: ['./src/styles/custom.css'],
			social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/riptide-project/framework' }],
			sidebar: [
				{
					label: 'Start Here',
					items: [
						{ label: 'Getting Started', slug: 'guides/getting-started' },
						{ label: 'Project Structure', slug: 'guides/project-structure' },
					],
				},
				{
					label: 'Concepts',
					items: [
						{ label: 'Module Lifecycle', slug: 'guides/module-lifecycle' },
						{ label: 'Plugins', slug: 'guides/plugins' },
						{ label: 'Luau Directives', slug: 'guides/luau-directives' },
					],
				},
				{
					label: 'Examples',
					items: [
						{ label: 'Server Service', slug: 'examples/server-service' },
						{ label: 'Typed Network and State', slug: 'examples/typed-network-state' },
						{ label: 'Framework Plugin', slug: 'examples/framework-plugin' },
					],
				},
				{
					label: 'Migration',
					items: [
						{ label: 'From 0.8.2 Stable', slug: 'migration/from-0-8-2' },
						{ label: 'From Maelstrom-1', slug: 'migration/from-maelstrom-1' },
					],
				},
				{
					label: 'API Reference',
					items: [
						{ label: 'Network', slug: 'api/network' },
						{ label: 'State Replication', slug: 'api/state-replication' },
						{ label: 'Component Service', slug: 'api/component-service' },
						{ label: 'State Machine', slug: 'api/state-machine' },
						{ label: 'Module System', slug: 'api/module-loader' },
						{ label: 'Player Lifecycle', slug: 'api/player-lifecycle' },
						{ label: 'Utilities', slug: 'api/utilities' },
					],
				},
			],
		}),
	],
});
