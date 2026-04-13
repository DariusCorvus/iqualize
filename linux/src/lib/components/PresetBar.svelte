<script lang="ts">
	import {
		allPresets,
		activePreset,
		presetModified,
		canUndo,
		canRedo,
		selectPreset,
		undo,
		redo,
		saveCurrentPreset,
		savePresetAs,
		deletePreset,
		resetPreset,
		type EQPresetData
	} from '$lib/stores/presets';

	let showSaveAs = false;
	let saveAsName = '';

	$: builtInPresets = $allPresets.filter((p) => p.isBuiltIn);
	$: customPresets = $allPresets.filter((p) => !p.isBuiltIn);

	function onPresetChange(e: Event) {
		const id = (e.target as HTMLSelectElement).value;
		selectPreset(id);
	}

	function handleSaveAs() {
		if (saveAsName.trim()) {
			savePresetAs(saveAsName.trim());
			showSaveAs = false;
			saveAsName = '';
		}
	}

	function handleDelete() {
		if ($activePreset && !$activePreset.isBuiltIn) {
			if (confirm(`Delete "${$activePreset.name}"?`)) {
				deletePreset($activePreset.id);
			}
		}
	}
</script>

<div class="preset-bar">
	<button class="icon-btn" disabled={!$canUndo} on:click={undo} title="Undo">&#x21B6;</button>
	<button class="icon-btn" disabled={!$canRedo} on:click={redo} title="Redo">&#x21B7;</button>

	<select class="preset-select" value={$activePreset?.id ?? ''} on:change={onPresetChange}>
		<optgroup label="Built-in">
			{#each builtInPresets as preset}
				<option value={preset.id}>{preset.name}</option>
			{/each}
		</optgroup>
		{#if customPresets.length > 0}
			<optgroup label="Custom">
				{#each customPresets as preset}
					<option value={preset.id}>{preset.name}</option>
				{/each}
			</optgroup>
		{/if}
	</select>

	{#if $presetModified}
		<span class="modified">*</span>
	{/if}

	<button on:click={saveCurrentPreset}>Save</button>
	<button on:click={() => (showSaveAs = true)}>Save As</button>
	<button disabled={!$presetModified} on:click={resetPreset}>Reset</button>
	<button
		class="delete-btn"
		disabled={!$activePreset || $activePreset.isBuiltIn}
		on:click={handleDelete}
	>
		Delete
	</button>
</div>

{#if showSaveAs}
	<!-- svelte-ignore a11y_click_events_have_key_events -->
	<!-- svelte-ignore a11y_no_static_element_interactions -->
	<div class="save-as-overlay" on:click={() => (showSaveAs = false)}>
		<!-- svelte-ignore a11y_click_events_have_key_events -->
		<!-- svelte-ignore a11y_no_static_element_interactions -->
		<div class="save-as-dialog" on:click|stopPropagation>
			<label>
				Preset name:
				<input
					type="text"
					bind:value={saveAsName}
					on:keydown={(e) => e.key === 'Enter' && handleSaveAs()}
					autofocus
				/>
			</label>
			<div class="dialog-buttons">
				<button on:click={() => (showSaveAs = false)}>Cancel</button>
				<button on:click={handleSaveAs}>Save</button>
			</div>
		</div>
	</div>
{/if}

<style>
	.preset-bar {
		display: flex;
		align-items: center;
		gap: 6px;
		padding: 4px 0;
	}

	.icon-btn {
		padding: 4px 8px;
		font-size: 14px;
		line-height: 1;
	}

	.preset-select {
		flex: 1;
		min-width: 140px;
	}

	.modified {
		color: var(--accent);
		font-weight: bold;
		font-size: 16px;
	}

	.delete-btn:not(:disabled) {
		color: var(--danger);
	}

	.save-as-overlay {
		position: fixed;
		inset: 0;
		background: rgba(0, 0, 0, 0.5);
		display: flex;
		align-items: center;
		justify-content: center;
		z-index: 100;
	}

	.save-as-dialog {
		background: var(--bg-secondary);
		border: 1px solid var(--border);
		border-radius: 8px;
		padding: 16px;
		min-width: 280px;
	}

	.save-as-dialog label {
		display: block;
		margin-bottom: 12px;
		color: var(--text-secondary);
		font-size: 12px;
	}

	.save-as-dialog input {
		display: block;
		width: 100%;
		margin-top: 4px;
		padding: 6px 8px;
		font-size: 13px;
	}

	.dialog-buttons {
		display: flex;
		justify-content: flex-end;
		gap: 8px;
	}
</style>
