<script lang="ts">
	import {
		appState,
		setBypass,
		setInputGain,
		setOutputGain,
		setBalance,
		setPeakLimiter,
		setSplitChannel,
		setSpectrumEnabled,
		updateAppState
	} from '$lib/stores/audio';
	import { formatGain, formatBalance } from '$lib/utils/format';

	$: state = $appState;

	function onBypassChange() {
		setBypass(!state.bypassed);
	}

	function onInputGainInput(e: Event) {
		const value = parseFloat((e.target as HTMLInputElement).value);
		setInputGain(value);
	}

	function onOutputGainInput(e: Event) {
		const value = parseFloat((e.target as HTMLInputElement).value);
		setOutputGain(value);
	}

	function onBalanceInput(e: Event) {
		let value = parseFloat((e.target as HTMLInputElement).value);
		// Snap to center
		if (Math.abs(value) < 0.05) value = 0;
		setBalance(value);
	}

	function onBalanceDblClick() {
		setBalance(0);
	}

	function onInputGainDblClick() {
		setInputGain(0);
	}

	function onOutputGainDblClick() {
		setOutputGain(0);
	}

	function onChannelChange(e: Event) {
		const value = (e.target as HTMLSelectElement).value;
		if (value === 'linked') {
			setSplitChannel(false);
			updateAppState({ activeChannel: null });
		} else {
			setSplitChannel(true);
			updateAppState({ activeChannel: value });
		}
	}

	function onPreEqToggle() {
		setSpectrumEnabled(!state.preEqSpectrumEnabled, state.postEqSpectrumEnabled);
	}

	function onPostEqToggle() {
		setSpectrumEnabled(state.preEqSpectrumEnabled, !state.postEqSpectrumEnabled);
	}

	function onPeakLimiterToggle() {
		setPeakLimiter(!state.peakLimiter);
	}

	function onBandwidthModeChange() {
		updateAppState({ showBandwidthAsQ: !state.showBandwidthAsQ });
	}

	function onMaxGainChange(e: Event) {
		const value = parseFloat((e.target as HTMLSelectElement).value);
		updateAppState({ maxGainDb: value });
	}

	function onAutoScaleChange() {
		updateAppState({ autoScale: !state.autoScale });
	}
</script>

<!-- Row 3: Audio Controls -->
<div class="controls-row">
	<label class="checkbox-label">
		<input type="checkbox" checked={state.bypassed} on:change={onBypassChange} />
		Bypass
	</label>

	<div class="separator"></div>

	<!-- svelte-ignore a11y_no_static_element_interactions -->
	<div class="gain-control" on:dblclick={onInputGainDblClick}>
		<span class="control-label">In</span>
		<input
			type="range"
			min="-24"
			max="24"
			step="0.5"
			value={state.inputGainDb}
			on:input={onInputGainInput}
			class="gain-range"
		/>
		<span class="control-value monospace">{formatGain(state.inputGainDb)}</span>
	</div>

	<!-- svelte-ignore a11y_no_static_element_interactions -->
	<div class="gain-control" on:dblclick={onOutputGainDblClick}>
		<span class="control-label">Out</span>
		<input
			type="range"
			min="-24"
			max="24"
			step="0.5"
			value={state.outputGainDb}
			on:input={onOutputGainInput}
			class="gain-range"
		/>
		<span class="control-value monospace">{formatGain(state.outputGainDb)}</span>
	</div>

	<div class="separator"></div>

	<!-- svelte-ignore a11y_no_static_element_interactions -->
	<div class="balance-control" on:dblclick={onBalanceDblClick}>
		<span class="control-label">Bal</span>
		<input
			type="range"
			min="-1"
			max="1"
			step="0.01"
			value={state.balance}
			on:input={onBalanceInput}
			class="balance-range"
		/>
		<span class="control-value monospace">{formatBalance(state.balance)}</span>
	</div>

	<div class="separator"></div>

	<select
		class="channel-select"
		value={state.splitChannelEnabled ? state.activeChannel ?? 'left' : 'linked'}
		on:change={onChannelChange}
	>
		<option value="linked">Linked</option>
		<option value="left">L</option>
		<option value="right">R</option>
	</select>
</div>

<!-- Row 4: Display Controls -->
<div class="display-row">
	<label class="checkbox-label">
		<input type="checkbox" checked={state.preEqSpectrumEnabled} on:change={onPreEqToggle} />
		Pre-EQ
	</label>

	<label class="checkbox-label">
		<input type="checkbox" checked={state.postEqSpectrumEnabled} on:change={onPostEqToggle} />
		Post-EQ
	</label>

	<button class="mode-btn" on:click={onBandwidthModeChange}>
		{state.showBandwidthAsQ ? 'Q' : 'Oct'}
	</button>

	<label class="checkbox-label">
		<input type="checkbox" checked={state.peakLimiter} on:change={onPeakLimiterToggle} />
		Limiter
	</label>

	<div class="spacer"></div>

	<span class="control-label">Max</span>
	<select class="max-gain-select" value={state.maxGainDb} on:change={onMaxGainChange} disabled={state.autoScale}>
		<option value={6}>6 dB</option>
		<option value={12}>12 dB</option>
		<option value={18}>18 dB</option>
		<option value={24}>24 dB</option>
	</select>

	<label class="checkbox-label">
		<input type="checkbox" checked={state.autoScale} on:change={onAutoScaleChange} />
		Auto
	</label>
</div>

<style>
	.controls-row,
	.display-row {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 4px 0;
		font-size: 11px;
	}

	.separator {
		width: 1px;
		height: 16px;
		background: var(--border);
	}

	.spacer {
		flex: 1;
	}

	.checkbox-label {
		display: flex;
		align-items: center;
		gap: 4px;
		cursor: pointer;
		white-space: nowrap;
		color: var(--text-secondary);
	}

	.gain-control,
	.balance-control {
		display: flex;
		align-items: center;
		gap: 4px;
	}

	.control-label {
		color: var(--text-tertiary);
		font-size: 11px;
		white-space: nowrap;
	}

	.control-value {
		font-size: 10px;
		color: var(--text-secondary);
		min-width: 44px;
		text-align: right;
	}

	.gain-range {
		width: 80px;
		accent-color: var(--accent);
	}

	.balance-range {
		width: 60px;
		accent-color: var(--accent);
	}

	.channel-select {
		font-size: 11px;
		padding: 2px 4px;
	}

	.mode-btn {
		padding: 2px 8px;
		font-size: 10px;
		min-width: 32px;
	}

	.max-gain-select {
		font-size: 11px;
		padding: 2px 4px;
	}
</style>
