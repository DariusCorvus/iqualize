/** Formatting helpers ported from macos/Sources/iQualize/EQModels.swift */

export function formatFrequency(hz: number): string {
	if (hz >= 1000) {
		const k = hz / 1000;
		if (k === Math.floor(k)) return `${k} kHz`;
		return `${k.toFixed(1)} kHz`;
	}
	if (hz === Math.floor(hz)) return `${hz} Hz`;
	return `${hz.toFixed(1)} Hz`;
}

export function formatGain(db: number): string {
	if (db === 0) return '0 dB';
	if (db === Math.floor(db)) return `${db > 0 ? '+' : ''}${db} dB`;
	return `${db > 0 ? '+' : ''}${db.toFixed(1)} dB`;
}

export function formatBandwidth(bw: number, asQ: boolean): string {
	if (asQ) {
		const q = octavesToQ(bw);
		if (q >= 10) return `Q ${q.toFixed(0)}`;
		return `Q ${q.toFixed(2)}`;
	}
	if (bw === Math.floor(bw)) return `${bw} oct`;
	return `${bw.toFixed(1)} oct`;
}

export function octavesToQ(bw: number): number {
	const p = Math.pow(2, bw);
	return Math.sqrt(p) / (p - 1);
}

export function qToOctaves(q: number): number {
	return (2 * Math.asinh(1 / (2 * q))) / Math.log(2);
}

export function formatBalance(value: number): string {
	if (Math.abs(value) < 0.01) return 'C';
	if (value < 0) return `${Math.round(Math.abs(value) * 100)}L`;
	return `${Math.round(value * 100)}R`;
}

/** Map frequency to X position (log scale, 20Hz-20kHz). */
export function freqToX(freq: number, width: number): number {
	return (Math.log10(freq / 20) / 3) * width;
}

/** Map X position to frequency. */
export function xToFreq(x: number, width: number): number {
	return 20 * Math.pow(1000, x / width);
}

/** Map gain dB to Y position. */
export function gainToY(gain: number, height: number, maxGain: number): number {
	return height / 2 - (gain / maxGain) * (height / 2);
}

/** Map Y position to gain. */
export function yToGain(y: number, height: number, maxGain: number): number {
	return ((height / 2 - y) / (height / 2)) * maxGain;
}

export const FILTER_TYPES = [
	{ value: 'parametric', label: 'Bell' },
	{ value: 'lowShelf', label: 'Lo Shelf' },
	{ value: 'highShelf', label: 'Hi Shelf' },
	{ value: 'lowPass', label: 'Lo Pass' },
	{ value: 'highPass', label: 'Hi Pass' },
	{ value: 'bandPass', label: 'Band Pass' },
	{ value: 'notch', label: 'Notch' }
] as const;
