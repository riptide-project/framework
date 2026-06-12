import { defineCollection, z } from 'astro:content';
import { docsLoader } from '@astrojs/starlight/loaders';
import { docsSchema } from '@astrojs/starlight/schema';

export const collections = {
	docs: defineCollection({
		loader: docsLoader(),
		schema: docsSchema({
			extend: z.object({
				banner: z.object({
					content: z.string()
				}).optional().default(
					process.env.MAELSTROM === 'true'
					? { content: '🌊 You are viewing documentation for the <b>Maelstrom</b> pre-release channel. Pin a <a href="https://github.com/riptide-project/framework/releases">stable release</a> for production.' }
					: undefined
				),
			}),
		}),
	}),
};
