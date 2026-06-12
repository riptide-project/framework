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
			banner: process.env.MAELSTROM === 'true' ? {
				content: '🌊 You are viewing documentation for the <b>Maelstrom</b> pre-release channel. Pin a <a href="https://github.com/riptide-project/framework/releases">stable release</a> for production.',
			} : undefined,
			logo: {
				src: './src/assets/logo.png',
			},
			favicon: 'favicon.png',
			customCss: ['./src/styles/custom.css'],
			social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/riptide-project/framework' }],
			sidebar: [
				{
					label: 'Guides',
					items: [
						{ label: 'Getting Started', slug: 'guides/getting-started' },
						{ label: 'Project Structure', slug: 'guides/project-structure' },
						{ label: 'Module Lifecycle', slug: 'guides/module-lifecycle' },
						{ label: 'Plugins', slug: 'guides/plugins' },
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
