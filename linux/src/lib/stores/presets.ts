import { writable, derived, get } from 'svelte/store';
import { invoke } from '@tauri-apps/api/core';
import type { EQBand } from '$lib/utils/biquad-response';
import { appState } from './audio';

export interface EQPresetData {
	id: string;
	name: string;
	bands: EQBand[];
	rightBands: EQBand[] | null;
	isBuiltIn: boolean;
}

export const allPresets = writable<EQPresetData[]>([]);
export const activePreset = writable<EQPresetData | null>(null);
export const activeBands = writable<EQBand[]>([]);
export const presetModified = writable(false);

// Undo/redo stacks
const undoStack = writable<EQBand[][]>([]);
const redoStack = writable<EQBand[][]>([]);
export const canUndo = derived(undoStack, ($s) => $s.length > 0);
export const canRedo = derived(redoStack, ($s) => $s.length > 0);

export async function loadPresets() {
	try {
		const presets = await invoke<EQPresetData[]>('get_all_presets');
		allPresets.set(presets);
	} catch (e) {
		console.error('Failed to load presets:', e);
	}
}

export async function selectPreset(id: string) {
	try {
		const preset = await invoke<EQPresetData>('set_active_preset', { id });
		activePreset.set(preset);
		activeBands.set(preset.bands);
		presetModified.set(false);
		undoStack.set([]);
		redoStack.set([]);
	} catch (e) {
		console.error('Failed to select preset:', e);
	}
}

export function pushUndo(bands: EQBand[]) {
	undoStack.update((s) => [...s, bands]);
	redoStack.set([]);
}

export function undo() {
	const stack = get(undoStack);
	if (stack.length === 0) return;
	const current = get(activeBands);
	redoStack.update((s) => [...s, current]);
	const prev = stack[stack.length - 1];
	undoStack.update((s) => s.slice(0, -1));
	activeBands.set(prev);
	presetModified.set(true);
	invoke('update_bands', { bands: prev, channel: null }).catch(console.error);
}

export function redo() {
	const stack = get(redoStack);
	if (stack.length === 0) return;
	const current = get(activeBands);
	undoStack.update((s) => [...s, current]);
	const next = stack[stack.length - 1];
	redoStack.update((s) => s.slice(0, -1));
	activeBands.set(next);
	presetModified.set(true);
	invoke('update_bands', { bands: next, channel: null }).catch(console.error);
}

export async function updateBand(index: number, changes: Partial<EQBand>) {
	const bands = get(activeBands);
	pushUndo([...bands]);
	const updated = bands.map((b, i) => (i === index ? { ...b, ...changes } : b));
	activeBands.set(updated);
	presetModified.set(true);
	await invoke('update_bands', { bands: updated, channel: null });
}

export async function updateAllBands(bands: EQBand[]) {
	const current = get(activeBands);
	pushUndo([...current]);
	activeBands.set(bands);
	presetModified.set(true);
	await invoke('update_bands', { bands, channel: null });
}

export async function addBand(band: EQBand, atIndex?: number) {
	const bands = get(activeBands);
	if (bands.length >= 31) return;
	pushUndo([...bands]);
	const newBands = [...bands];
	if (atIndex !== undefined) {
		newBands.splice(atIndex, 0, band);
	} else {
		newBands.push(band);
	}
	activeBands.set(newBands);
	presetModified.set(true);
	await invoke('update_bands', { bands: newBands, channel: null });
}

export async function removeBand(index: number) {
	const bands = get(activeBands);
	if (bands.length <= 1) return;
	pushUndo([...bands]);
	const newBands = bands.filter((_, i) => i !== index);
	activeBands.set(newBands);
	presetModified.set(true);
	await invoke('update_bands', { bands: newBands, channel: null });
}

export async function saveCurrentPreset() {
	const preset = get(activePreset);
	const bands = get(activeBands);
	if (!preset) return;

	if (preset.isBuiltIn) {
		// Fork to a new custom preset
		const newPreset: EQPresetData = {
			id: crypto.randomUUID(),
			name: `${preset.name} (Custom)`,
			bands,
			rightBands: null,
			isBuiltIn: false
		};
		await invoke('save_custom_preset', { preset: newPreset });
		await selectPreset(newPreset.id);
		await loadPresets();
	} else {
		const updated = { ...preset, bands };
		await invoke('save_custom_preset', { preset: updated });
		activePreset.set(updated);
		presetModified.set(false);
		await loadPresets();
	}
}

export async function savePresetAs(name: string) {
	const bands = get(activeBands);
	const newPreset: EQPresetData = {
		id: crypto.randomUUID(),
		name,
		bands,
		rightBands: null,
		isBuiltIn: false
	};
	await invoke('save_custom_preset', { preset: newPreset });
	await selectPreset(newPreset.id);
	await loadPresets();
}

export async function deletePreset(id: string) {
	await invoke('delete_custom_preset', { id });
	await loadPresets();
	// Select Flat after deletion
	await selectPreset('00000000-0000-0000-0000-000000000001');
}

export async function resetPreset() {
	const preset = get(activePreset);
	if (!preset) return;
	activeBands.set(preset.bands);
	presetModified.set(false);
	undoStack.set([]);
	redoStack.set([]);
	await invoke('update_bands', { bands: preset.bands, channel: null });
}

export function suggestNewBandFrequency(bands: EQBand[]): number {
	if (bands.length === 0) return 1000;
	const sorted = [...bands].sort((a, b) => a.frequency - b.frequency);
	const freqs = sorted.map((b) => b.frequency);

	let bestFreq = freqs[0] / 2;
	let bestGap = Math.log2(freqs[0] / 20);

	for (let i = 1; i < freqs.length; i++) {
		const gap = Math.log2(freqs[i] / freqs[i - 1]);
		if (gap > bestGap) {
			bestGap = gap;
			bestFreq = Math.sqrt(freqs[i] * freqs[i - 1]);
		}
	}

	const topGap = Math.log2(20000 / freqs[freqs.length - 1]);
	if (topGap > bestGap) {
		bestFreq = freqs[freqs.length - 1] * 2;
	}

	return Math.min(Math.max(bestFreq, 20), 20000);
}
