export const releases = [
	{ version: '0.8.2', channel: 'Stable', label: 'Latest stable' },
	{ version: '0.8.1', channel: 'Stable', label: 'Stable' },
	{ version: '0.8.0', channel: 'Stable', label: 'Stable' },
	{ version: '0.7.1', channel: 'Stable', label: 'Stable' },
	{ version: '0.7.0', channel: 'Stable', label: 'Stable' },
	{ version: '0.6.0', channel: 'Stable', label: 'Stable' },
	{ version: '0.5.0', channel: 'Stable', label: 'Stable' },
	{ version: '0.4.0', channel: 'Stable', label: 'Stable' },
	{ version: '0.3.0', channel: 'Stable', label: 'Stable' },
	{ version: '0.9.0-maelstrom.2', channel: 'Preview', label: 'Earlier preview' },
	{ version: '0.9.0-maelstrom.3', channel: 'Preview', label: 'Latest preview' },
] as const;

export const latestStable = releases[0];
export const latestPreview = releases[releases.length - 1];

export const versionPath = (version: string) => `/framework/versions/${version}/`;
