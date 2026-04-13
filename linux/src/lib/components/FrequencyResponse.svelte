<script lang="ts">
	import { onMount } from 'svelte';
	import {
		logFrequencies,
		compositeResponse,
		perBandResponses,
		type EQBand
	} from '$lib/utils/biquad-response';
	import { freqToX, gainToY } from '$lib/utils/format';
	import { preEqSpectrum, postEqSpectrum } from '$lib/stores/spectrum';
	import type { SpectrumChannelData } from '$lib/stores/spectrum';

	export let bands: EQBand[] = [];
	export let maxGain: number = 12;
	export let sampleRate: number = 48000;
	export let selectedBandIndex: number = -1;
	export let preEqEnabled: boolean = false;
	export let postEqEnabled: boolean = false;

	let canvas: HTMLCanvasElement;
	let ctx: CanvasRenderingContext2D;
	let width = 0;
	let height = 0;
	let animFrameId: number;

	// Pre-computed log frequencies for response curves
	const freqs = logFrequencies(512);

	// Bin edge frequencies for spectrum (128 bins)
	const binEdges: number[] = [];
	for (let i = 0; i <= 128; i++) {
		binEdges.push(20 * Math.pow(1000, i / 128));
	}

	onMount(() => {
		ctx = canvas.getContext('2d')!;
		resizeCanvas();
		const observer = new ResizeObserver(() => resizeCanvas());
		observer.observe(canvas.parentElement!);

		function animate() {
			draw();
			animFrameId = requestAnimationFrame(animate);
		}
		animFrameId = requestAnimationFrame(animate);

		return () => {
			cancelAnimationFrame(animFrameId);
			observer.disconnect();
		};
	});

	function resizeCanvas() {
		const dpr = window.devicePixelRatio || 1;
		const rect = canvas.parentElement!.getBoundingClientRect();
		width = rect.width;
		height = rect.height;
		canvas.width = width * dpr;
		canvas.height = height * dpr;
		canvas.style.width = `${width}px`;
		canvas.style.height = `${height}px`;
		ctx?.scale(dpr, dpr);
	}

	function draw() {
		if (!ctx || width === 0) return;
		ctx.clearRect(0, 0, width, height);
		drawGrid();
		drawSpectrum();
		drawBandFills();
		drawCompositeCurve();
		drawAnchorDots();
	}

	function drawGrid() {
		ctx.strokeStyle = 'rgba(255, 255, 255, 0.04)';
		ctx.lineWidth = 0.5;

		// Frequency grid lines: 20, 50, 100, 200, 500, 1k, 2k, 5k, 10k, 20k
		const gridFreqs = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000];
		for (const f of gridFreqs) {
			const x = freqToX(f, width);
			ctx.beginPath();
			ctx.moveTo(x, 0);
			ctx.lineTo(x, height);
			ctx.stroke();
		}

		// dB grid lines
		const step = maxGain <= 6 ? 1 : maxGain <= 12 ? 3 : 6;
		for (let db = -maxGain; db <= maxGain; db += step) {
			const y = gainToY(db, height, maxGain);
			if (db === 0) {
				ctx.strokeStyle = 'rgba(255, 255, 255, 0.1)';
				ctx.lineWidth = 0.75;
			} else {
				ctx.strokeStyle = 'rgba(255, 255, 255, 0.04)';
				ctx.lineWidth = 0.5;
			}
			ctx.beginPath();
			ctx.moveTo(0, y);
			ctx.lineTo(width, y);
			ctx.stroke();
		}
	}

	function drawSpectrum() {
		let preData: SpectrumChannelData | null = null;
		let postData: SpectrumChannelData | null = null;

		preEqSpectrum.subscribe((v) => (preData = v))();
		postEqSpectrum.subscribe((v) => (postData = v))();

		if (preEqEnabled && preData) {
			drawSpectrumLine(preData.magnitudes, 'rgba(255, 255, 255, 0.4)', false);
			drawSpectrumLine(preData.peaks, 'rgba(255, 255, 255, 0.2)', false);
		}

		if (postEqEnabled && postData) {
			drawSpectrumLine(postData.magnitudes, 'rgba(255, 255, 255, 0.5)', true);
			drawSpectrumLine(postData.peaks, 'rgba(255, 255, 255, 0.25)', false);
		}
	}

	function drawSpectrumLine(mags: number[], color: string, fill: boolean) {
		if (!mags || mags.length === 0) return;

		ctx.beginPath();
		const zeroY = gainToY(-90, height, maxGain);

		for (let i = 0; i < mags.length; i++) {
			const freq = Math.sqrt(binEdges[i] * binEdges[i + 1]);
			const x = freqToX(freq, width);
			// Map -90..0 dB to display range
			const displayDb = ((mags[i] + 90) / 90) * maxGain - maxGain;
			const y = gainToY(displayDb, height, maxGain);
			if (i === 0) ctx.moveTo(x, y);
			else ctx.lineTo(x, y);
		}

		if (fill) {
			const lastFreq = Math.sqrt(binEdges[mags.length - 1] * binEdges[mags.length]);
			ctx.lineTo(freqToX(lastFreq, width), height);
			ctx.lineTo(freqToX(20, width), height);
			ctx.closePath();
			ctx.fillStyle = 'rgba(255, 255, 255, 0.15)';
			ctx.fill();
		}

		ctx.strokeStyle = color;
		ctx.lineWidth = 1;
		ctx.stroke();
	}

	function drawBandFills() {
		if (bands.length === 0) return;
		const perBand = perBandResponses(bands, sampleRate, freqs);

		for (let b = 0; b < bands.length; b++) {
			const response = perBand[b];
			const isBoost = bands[b].gain >= 0;
			ctx.fillStyle = isBoost
				? 'rgba(76, 141, 255, 0.035)'
				: 'rgba(76, 141, 255, 0.06)';

			ctx.beginPath();
			const zeroY = gainToY(0, height, maxGain);
			ctx.moveTo(freqToX(freqs[0], width), zeroY);

			for (let i = 0; i < freqs.length; i++) {
				ctx.lineTo(freqToX(freqs[i], width), gainToY(response[i], height, maxGain));
			}

			ctx.lineTo(freqToX(freqs[freqs.length - 1], width), zeroY);
			ctx.closePath();
			ctx.fill();
		}
	}

	function drawCompositeCurve() {
		if (bands.length === 0) return;
		const response = compositeResponse(bands, sampleRate, freqs);

		ctx.beginPath();
		ctx.strokeStyle = 'rgba(76, 141, 255, 0.65)';
		ctx.lineWidth = 2;

		for (let i = 0; i < freqs.length; i++) {
			const x = freqToX(freqs[i], width);
			const y = gainToY(response[i], height, maxGain);
			if (i === 0) ctx.moveTo(x, y);
			else ctx.lineTo(x, y);
		}
		ctx.stroke();
	}

	function drawAnchorDots() {
		if (bands.length === 0) return;
		const composite = compositeResponse(bands, sampleRate, freqs);

		for (let b = 0; b < bands.length; b++) {
			const freq = bands[b].frequency;
			const x = freqToX(freq, width);
			// Find composite gain at this frequency
			const freqIdx = freqs.findIndex((f) => f >= freq);
			const compGain = freqIdx >= 0 ? composite[freqIdx] : 0;
			const y = gainToY(compGain, height, maxGain);

			const isSelected = b === selectedBandIndex;

			// Outer circle
			ctx.beginPath();
			ctx.arc(x, y, isSelected ? 6 : 5, 0, Math.PI * 2);
			ctx.fillStyle = isSelected
				? 'rgba(76, 141, 255, 0.3)'
				: 'rgba(76, 141, 255, 0.15)';
			ctx.fill();

			// Inner dot
			ctx.beginPath();
			ctx.arc(x, y, isSelected ? 3 : 2.5, 0, Math.PI * 2);
			ctx.fillStyle = isSelected
				? 'rgba(76, 141, 255, 1.0)'
				: 'rgba(76, 141, 255, 0.7)';
			ctx.fill();
		}
	}
</script>

<div class="freq-response">
	<canvas bind:this={canvas}></canvas>
</div>

<style>
	.freq-response {
		width: 100%;
		height: 100%;
		position: relative;
	}
	canvas {
		position: absolute;
		top: 0;
		left: 0;
	}
</style>
