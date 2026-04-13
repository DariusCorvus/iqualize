import { writable, derived } from 'svelte/store';
import { invoke } from '@tauri-apps/api/core';
import type { EQBand, FilterType } from '$lib/utils/biquad-response';

export interface AppState {
	isEnabled: boolean;
	selectedPresetId: string;
	peakLimiter: boolean;
	windowOpen: boolean;
	maxGainDb: number;
	bypassed: boolean;
	autoScale: boolean;
	preEqSpectrumEnabled: boolean;
	postEqSpectrumEnabled: boolean;
	startAtLogin: boolean;
	balance: number;
	splitChannelEnabled: boolean;
	activeChannel: string | null;
	inputGainDb: number;
	outputGainDb: number;
	showBandwidthAsQ: boolean;
}

const defaultState: AppState = {
	isEnabled: false,
	selectedPresetId: '00000000-0000-0000-0000-000000000001',
	peakLimiter: true,
	windowOpen: false,
	maxGainDb: 12,
	bypassed: false,
	autoScale: true,
	preEqSpectrumEnabled: false,
	postEqSpectrumEnabled: false,
	startAtLogin: false,
	balance: 0,
	splitChannelEnabled: false,
	activeChannel: null,
	inputGainDb: 0,
	outputGainDb: 0,
	showBandwidthAsQ: true
};

export const appState = writable<AppState>(defaultState);
export const bypassed = derived(appState, ($s) => $s.bypassed);
export const maxGainDb = derived(appState, ($s) => $s.maxGainDb);
export const autoScale = derived(appState, ($s) => $s.autoScale);

export async function loadState() {
	try {
		const state = await invoke<AppState>('get_state');
		appState.set(state);
	} catch (e) {
		console.error('Failed to load state:', e);
	}
}

export async function setBypass(value: boolean) {
	appState.update((s) => ({ ...s, bypassed: value }));
	await invoke('set_bypass', { bypassed: value });
}

export async function setInputGain(db: number) {
	appState.update((s) => ({ ...s, inputGainDb: db }));
	await invoke('set_input_gain', { db });
}

export async function setOutputGain(db: number) {
	appState.update((s) => ({ ...s, outputGainDb: db }));
	await invoke('set_output_gain', { db });
}

export async function setBalance(value: number) {
	appState.update((s) => ({ ...s, balance: value }));
	await invoke('set_balance', { value });
}

export async function setPeakLimiter(enabled: boolean) {
	appState.update((s) => ({ ...s, peakLimiter: enabled }));
	await invoke('set_peak_limiter', { enabled });
}

export async function setSplitChannel(enabled: boolean) {
	appState.update((s) => ({ ...s, splitChannelEnabled: enabled }));
	await invoke('set_split_channel', { enabled });
}

export async function setSpectrumEnabled(preEq: boolean, postEq: boolean) {
	appState.update((s) => ({
		...s,
		preEqSpectrumEnabled: preEq,
		postEqSpectrumEnabled: postEq
	}));
	await invoke('set_spectrum_enabled', { preEq, postEq });
}

export async function updateAppState(partial: Partial<AppState>) {
	appState.update((s) => {
		const updated = { ...s, ...partial };
		invoke('save_state', { state: updated }).catch(console.error);
		return updated;
	});
}
