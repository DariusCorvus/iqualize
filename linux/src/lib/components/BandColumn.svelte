<script lang="ts">
	import type { EQBand, FilterType } from '$lib/utils/biquad-response';
	import { formatFrequency, formatGain, formatBandwidth, FILTER_TYPES } from '$lib/utils/format';
	import { createEventDispatcher } from 'svelte';

	export let band: EQBand;
	export let index: number;
	export let maxGain: number = 12;
	export let showBandwidthAsQ: boolean = true;
	export let selected: boolean = false;

	const dispatch = createEventDispatcher<{
		gainChange: { index: number; gain: number };
		freqChange: { index: number; frequency: number };
		bwChange: { index: number; bandwidth: number };
		filterTypeChange: { index: number; filterType: FilterType };
		select: { index: number };
		remove: { index: number };
		addLeft: { index: number };
		addRight: { index: number };
	}>();

	let gainInput = '';
	let freqInput = '';
	let bwInput = '';

	$: gainInput = formatGain(band.gain);
	$: freqInput = formatFrequency(band.frequency);
	$: bwInput = formatBandwidth(band.bandwidth, showBandwidthAsQ);

	function onGainSliderInput(e: Event) {
		const value = parseFloat((e.target as HTMLInputElement).value);
		dispatch('gainChange', { index, gain: value });
	}

	function onGainInputBlur(e: FocusEvent) {
		const text = (e.target as HTMLInputElement).value.replace(/[^\d.\-+]/g, '');
		const value = parseFloat(text);
		if (!isNaN(value)) {
			const clamped = Math.max(-maxGain, Math.min(maxGain, value));
			dispatch('gainChange', { index, gain: Math.round(clamped * 2) / 2 });
		}
	}

	function onFreqInputBlur(e: FocusEvent) {
		let text = (e.target as HTMLInputElement).value.toLowerCase().trim();
		let multiplier = 1;
		if (text.includes('k')) {
			text = text.replace('khz', '').replace('k', '').trim();
			multiplier = 1000;
		} else {
			text = text.replace('hz', '').trim();
		}
		const value = parseFloat(text) * multiplier;
		if (!isNaN(value) && value >= 20 && value <= 20000) {
			dispatch('freqChange', { index, frequency: Math.round(value * 10) / 10 });
		}
	}

	function onBwInputBlur(e: FocusEvent) {
		const text = (e.target as HTMLInputElement).value.replace(/[^\d.]/g, '');
		const value = parseFloat(text);
		if (!isNaN(value) && value > 0) {
			const bw = showBandwidthAsQ
				? (2 * Math.asinh(1 / (2 * value))) / Math.log(2) // Q to octaves
				: value;
			const clamped = Math.max(0.1, Math.min(10, bw));
			dispatch('bwChange', { index, bandwidth: Math.round(clamped * 100) / 100 });
		}
	}

	function onFilterTypeChange(e: Event) {
		const value = (e.target as HTMLSelectElement).value as FilterType;
		dispatch('filterTypeChange', { index, filterType: value });
	}

	function onWheel(e: WheelEvent, type: 'gain' | 'freq' | 'bw') {
		e.preventDefault();
		const delta = e.deltaY > 0 ? -1 : 1;
		if (type === 'gain') {
			const newGain = Math.max(-maxGain, Math.min(maxGain, band.gain + delta * 0.5));
			dispatch('gainChange', { index, gain: newGain });
		} else if (type === 'freq') {
			// ±1 semitone (1/12 octave)
			const factor = Math.pow(2, delta / 12);
			const newFreq = Math.max(20, Math.min(20000, band.frequency * factor));
			dispatch('freqChange', { index, frequency: Math.round(newFreq * 10) / 10 });
		} else {
			const newBw = Math.max(0.1, Math.min(10, band.bandwidth + delta * 0.1));
			dispatch('bwChange', { index, bandwidth: Math.round(newBw * 100) / 100 });
		}
	}

	function handleContextMenu(e: MouseEvent) {
		e.preventDefault();
		// Context menu handled at parent level
	}
</script>

<!-- svelte-ignore a11y_click_events_have_key_events -->
<!-- svelte-ignore a11y_no_static_element_interactions -->
<div
	class="band-column"
	class:selected
	on:click={() => dispatch('select', { index })}
	on:contextmenu={handleContextMenu}
>
	<!-- Gain display -->
	<input
		class="gain-input monospace"
		type="text"
		value={gainInput}
		on:blur={onGainInputBlur}
		on:keydown={(e) => e.key === 'Enter' && (e.target as HTMLInputElement).blur()}
		on:wheel|preventDefault={(e) => onWheel(e, 'gain')}
	/>

	<!-- Gain slider -->
	<div class="slider-container">
		<input
			type="range"
			class="gain-slider"
			min={-maxGain}
			max={maxGain}
			step="0.5"
			value={band.gain}
			on:input={onGainSliderInput}
			orient="vertical"
		/>
	</div>

	<!-- Frequency -->
	<input
		class="freq-input monospace"
		type="text"
		value={freqInput}
		on:blur={onFreqInputBlur}
		on:keydown={(e) => e.key === 'Enter' && (e.target as HTMLInputElement).blur()}
		on:wheel|preventDefault={(e) => onWheel(e, 'freq')}
	/>

	<!-- Bandwidth/Q -->
	<input
		class="bw-input monospace"
		type="text"
		value={bwInput}
		on:blur={onBwInputBlur}
		on:keydown={(e) => e.key === 'Enter' && (e.target as HTMLInputElement).blur()}
		on:wheel|preventDefault={(e) => onWheel(e, 'bw')}
	/>

	<!-- Filter type -->
	<select class="filter-select" value={band.filterType} on:change={onFilterTypeChange}>
		{#each FILTER_TYPES as ft}
			<option value={ft.value}>{ft.label}</option>
		{/each}
	</select>
</div>

<style>
	.band-column {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 4px;
		padding: 4px;
		border-radius: 4px;
		min-width: 40px;
		flex: 1;
		transition: background-color 0.15s;
	}

	.band-column.selected {
		background: rgba(76, 141, 255, 0.08);
	}

	.band-column:hover {
		background: rgba(255, 255, 255, 0.03);
	}

	.gain-input,
	.freq-input,
	.bw-input {
		font-size: 9px;
		width: 100%;
		padding: 1px 2px;
	}

	.gain-input {
		font-size: 10px;
	}

	.slider-container {
		height: 140px;
		display: flex;
		align-items: center;
		justify-content: center;
	}

	.gain-slider {
		writing-mode: vertical-lr;
		direction: rtl;
		appearance: slider-vertical;
		width: 20px;
		height: 130px;
		accent-color: var(--accent);
	}

	.filter-select {
		font-size: 9px;
		width: 100%;
		padding: 1px 2px;
	}
</style>
