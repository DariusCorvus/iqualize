import { writable } from 'svelte/store';
import { listen } from '@tauri-apps/api/event';

export interface SpectrumChannelData {
	magnitudes: number[];
	peaks: number[];
}

export interface SpectrumPayload {
	preEq: SpectrumChannelData | null;
	postEq: SpectrumChannelData | null;
}

export const preEqSpectrum = writable<SpectrumChannelData | null>(null);
export const postEqSpectrum = writable<SpectrumChannelData | null>(null);

let unlistenFn: (() => void) | null = null;

export async function startListening() {
	if (unlistenFn) return;
	unlistenFn = await listen<SpectrumPayload>('spectrum-data', (event) => {
		preEqSpectrum.set(event.payload.preEq);
		postEqSpectrum.set(event.payload.postEq);
	});
}

export function stopListening() {
	if (unlistenFn) {
		unlistenFn();
		unlistenFn = null;
	}
}
