<script lang="ts">
	import { onMount } from 'svelte';
	import FrequencyResponse from './FrequencyResponse.svelte';
	import BandColumn from './BandColumn.svelte';
	import PresetBar from './PresetBar.svelte';
	import AudioControls from './AudioControls.svelte';
	import {
		activeBands,
		activePreset,
		presetModified,
		loadPresets,
		selectPreset,
		updateBand,
		addBand,
		removeBand,
		suggestNewBandFrequency
	} from '$lib/stores/presets';
	import { appState, loadState } from '$lib/stores/audio';
	import { startListening } from '$lib/stores/spectrum';
	import type { EQBand, FilterType } from '$lib/utils/biquad-response';

	let selectedBandIndex = -1;
	let sampleRate = 48000;

	$: bands = $activeBands;
	$: maxGain = $appState.maxGainDb;
	$: showBandwidthAsQ = $appState.showBandwidthAsQ;
	$: preEqEnabled = $appState.preEqSpectrumEnabled;
	$: postEqEnabled = $appState.postEqSpectrumEnabled;
	$: title = $activePreset
		? `iQualize — ${$activePreset.name}${$presetModified ? ' *' : ''}`
		: 'iQualize';

	onMount(async () => {
		await loadState();
		await loadPresets();

		// Select the active preset from saved state
		const state = $appState;
		if (state.selectedPresetId) {
			await selectPreset(state.selectedPresetId);
		}

		// Start spectrum event listener
		await startListening();
	});

	function onGainChange(e: CustomEvent<{ index: number; gain: number }>) {
		updateBand(e.detail.index, { gain: e.detail.gain });
	}

	function onFreqChange(e: CustomEvent<{ index: number; frequency: number }>) {
		updateBand(e.detail.index, { frequency: e.detail.frequency });
	}

	function onBwChange(e: CustomEvent<{ index: number; bandwidth: number }>) {
		updateBand(e.detail.index, { bandwidth: e.detail.bandwidth });
	}

	function onFilterTypeChange(e: CustomEvent<{ index: number; filterType: FilterType }>) {
		updateBand(e.detail.index, { filterType: e.detail.filterType });
	}

	function onBandSelect(e: CustomEvent<{ index: number }>) {
		selectedBandIndex = e.detail.index;
	}

	function handleAddBand(position: 'left' | 'right' | 'suggested') {
		const freq =
			position === 'suggested'
				? suggestNewBandFrequency(bands)
				: position === 'left'
					? Math.max(20, bands[0]?.frequency / 2 ?? 100)
					: Math.min(20000, (bands[bands.length - 1]?.frequency ?? 1000) * 2);

		const newBand: EQBand = {
			frequency: freq,
			gain: 0,
			bandwidth: 1.0,
			filterType: 'parametric'
		};

		if (position === 'left') {
			addBand(newBand, 0);
		} else if (position === 'right') {
			addBand(newBand, bands.length);
		} else {
			// Insert at sorted position
			const idx = bands.findIndex((b) => b.frequency > freq);
			addBand(newBand, idx >= 0 ? idx : bands.length);
		}
	}

	function handleRemoveBand(index: number) {
		if (bands.length > 1) {
			removeBand(index);
			if (selectedBandIndex >= bands.length - 1) {
				selectedBandIndex = Math.max(0, bands.length - 2);
			}
		}
	}

	function onKeyDown(e: KeyboardEvent) {
		if (e.ctrlKey && e.key === 'z') {
			e.preventDefault();
			if (e.shiftKey) {
				import('$lib/stores/presets').then(({ redo }) => redo());
			} else {
				import('$lib/stores/presets').then(({ undo }) => undo());
			}
		}
	}
</script>

<svelte:window on:keydown={onKeyDown} />
<svelte:head>
	<title>{title}</title>
</svelte:head>

<div class="eq-window">
	<!-- Preset Bar -->
	<div class="section preset-section">
		<PresetBar />
	</div>

	<div class="divider"></div>

	<!-- Frequency Response + Band Sliders -->
	<div class="section main-section">
		<div class="response-area">
			<FrequencyResponse
				{bands}
				{maxGain}
				{sampleRate}
				{selectedBandIndex}
				{preEqEnabled}
				{postEqEnabled}
			/>
		</div>
		<div class="bands-area">
			<!-- Add band button (left) -->
			<button class="add-band-btn left" on:click={() => handleAddBand('left')} title="Add band">
				+
			</button>

			{#each bands as band, i (i)}
				<BandColumn
					{band}
					index={i}
					{maxGain}
					{showBandwidthAsQ}
					selected={i === selectedBandIndex}
					on:gainChange={onGainChange}
					on:freqChange={onFreqChange}
					on:bwChange={onBwChange}
					on:filterTypeChange={onFilterTypeChange}
					on:select={onBandSelect}
					on:remove={() => handleRemoveBand(i)}
				/>
			{/each}

			<!-- Add band button (right) -->
			<button
				class="add-band-btn right"
				on:click={() => handleAddBand('right')}
				title="Add band"
			>
				+
			</button>
		</div>
	</div>

	<div class="divider"></div>

	<!-- Audio + Display Controls -->
	<div class="section controls-section">
		<AudioControls />
	</div>

	<!-- Output device info -->
	<div class="section device-section">
		<span class="device-label">Output: Default</span>
	</div>
</div>

<style>
	.eq-window {
		display: flex;
		flex-direction: column;
		height: 100vh;
		padding: 8px 16px;
		gap: 0;
	}

	.section {
		flex-shrink: 0;
	}

	.divider {
		height: 1px;
		background: var(--border);
		margin: 2px 0;
	}

	.main-section {
		flex: 1;
		display: flex;
		flex-direction: column;
		min-height: 0;
		gap: 4px;
	}

	.response-area {
		flex: 1;
		min-height: 80px;
		position: relative;
		border-radius: 4px;
		overflow: hidden;
		background: var(--bg-secondary);
	}

	.bands-area {
		display: flex;
		align-items: stretch;
		gap: 2px;
		overflow-x: auto;
		position: relative;
	}

	.add-band-btn {
		padding: 2px 6px;
		font-size: 16px;
		font-weight: bold;
		border-radius: 50%;
		width: 24px;
		height: 24px;
		display: flex;
		align-items: center;
		justify-content: center;
		align-self: center;
		opacity: 0.3;
		transition: opacity 0.15s;
		flex-shrink: 0;
	}

	.add-band-btn:hover {
		opacity: 1;
		background: var(--accent);
		color: white;
	}

	.controls-section {
		display: flex;
		flex-direction: column;
	}

	.device-section {
		padding: 2px 0;
	}

	.device-label {
		font-size: 11px;
		color: var(--text-tertiary);
	}
</style>
