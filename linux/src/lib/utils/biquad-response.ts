/** Client-side biquad frequency response calculation for real-time curve rendering.
 *  Ported from macos/Sources/iQualize/BiquadResponse.swift */

export type FilterType =
	| 'parametric'
	| 'lowShelf'
	| 'highShelf'
	| 'lowPass'
	| 'highPass'
	| 'bandPass'
	| 'notch';

export interface EQBand {
	frequency: number;
	gain: number;
	bandwidth: number;
	filterType: FilterType;
}

interface BiquadCoeffs {
	b0: number;
	b1: number;
	b2: number;
	a0: number;
	a1: number;
	a2: number;
}

/** Generate log-spaced frequencies from 20 Hz to 20 kHz. */
export function logFrequencies(count = 512): number[] {
	const freqs: number[] = new Array(count);
	for (let i = 0; i < count; i++) {
		const t = i / (count - 1);
		freqs[i] = 20 * Math.pow(1000, t);
	}
	return freqs;
}

/** Compute biquad coefficients using Audio EQ Cookbook formulas. */
export function coefficients(band: EQBand, sampleRate: number): BiquadCoeffs {
	const f0 = band.frequency;
	const gain = band.gain;
	const bw = Math.max(band.bandwidth, 0.05);

	const w0 = (2 * Math.PI * f0) / sampleRate;
	const cosW0 = Math.cos(w0);
	const sinW0 = Math.sin(w0);

	const sinW0Safe = Math.abs(sinW0) > 1e-10 ? sinW0 : 1e-10;
	const Q = 1 / (2 * Math.sinh((Math.log(2) / 2) * bw * (w0 / sinW0Safe)));
	const alpha = sinW0 / (2 * Q);

	switch (band.filterType) {
		case 'parametric': {
			const A = Math.pow(10, gain / 40);
			return {
				b0: 1 + alpha * A,
				b1: -2 * cosW0,
				b2: 1 - alpha * A,
				a0: 1 + alpha / A,
				a1: -2 * cosW0,
				a2: 1 - alpha / A
			};
		}
		case 'lowShelf': {
			const A = Math.pow(10, gain / 40);
			const twoSqrtAAlpha = 2 * Math.sqrt(A) * alpha;
			return {
				b0: A * (A + 1 - (A - 1) * cosW0 + twoSqrtAAlpha),
				b1: 2 * A * (A - 1 - (A + 1) * cosW0),
				b2: A * (A + 1 - (A - 1) * cosW0 - twoSqrtAAlpha),
				a0: A + 1 + (A - 1) * cosW0 + twoSqrtAAlpha,
				a1: -2 * (A - 1 + (A + 1) * cosW0),
				a2: A + 1 + (A - 1) * cosW0 - twoSqrtAAlpha
			};
		}
		case 'highShelf': {
			const A = Math.pow(10, gain / 40);
			const twoSqrtAAlpha = 2 * Math.sqrt(A) * alpha;
			return {
				b0: A * (A + 1 + (A - 1) * cosW0 + twoSqrtAAlpha),
				b1: -2 * A * (A - 1 + (A + 1) * cosW0),
				b2: A * (A + 1 + (A - 1) * cosW0 - twoSqrtAAlpha),
				a0: A + 1 - (A - 1) * cosW0 + twoSqrtAAlpha,
				a1: 2 * (A - 1 - (A + 1) * cosW0),
				a2: A + 1 - (A - 1) * cosW0 - twoSqrtAAlpha
			};
		}
		case 'lowPass':
			return {
				b0: (1 - cosW0) / 2,
				b1: 1 - cosW0,
				b2: (1 - cosW0) / 2,
				a0: 1 + alpha,
				a1: -2 * cosW0,
				a2: 1 - alpha
			};
		case 'highPass':
			return {
				b0: (1 + cosW0) / 2,
				b1: -(1 + cosW0),
				b2: (1 + cosW0) / 2,
				a0: 1 + alpha,
				a1: -2 * cosW0,
				a2: 1 - alpha
			};
		case 'bandPass':
			return {
				b0: alpha,
				b1: 0,
				b2: -alpha,
				a0: 1 + alpha,
				a1: -2 * cosW0,
				a2: 1 - alpha
			};
		case 'notch':
			return {
				b0: 1,
				b1: -2 * cosW0,
				b2: 1,
				a0: 1 + alpha,
				a1: -2 * cosW0,
				a2: 1 - alpha
			};
	}
}

/** Evaluate filter gain in dB at a given frequency. */
function gainDB(c: BiquadCoeffs, frequency: number, sampleRate: number): number {
	const w = (2 * Math.PI * frequency) / sampleRate;
	const cosW = Math.cos(w);
	const sinW = Math.sin(w);
	const cos2W = Math.cos(2 * w);
	const sin2W = Math.sin(2 * w);

	const nb0 = c.b0 / c.a0;
	const nb1 = c.b1 / c.a0;
	const nb2 = c.b2 / c.a0;
	const na1 = c.a1 / c.a0;
	const na2 = c.a2 / c.a0;

	const numReal = nb0 + nb1 * cosW + nb2 * cos2W;
	const numImag = -(nb1 * sinW + nb2 * sin2W);
	const denReal = 1 + na1 * cosW + na2 * cos2W;
	const denImag = -(na1 * sinW + na2 * sin2W);

	const numMagSq = numReal * numReal + numImag * numImag;
	const denMagSq = denReal * denReal + denImag * denImag;

	if (denMagSq < 1e-30) return -120;
	return 10 * Math.log10(numMagSq / denMagSq);
}

/** Composite frequency response: sum of all bands' dB contributions. */
export function compositeResponse(
	bands: EQBand[],
	sampleRate: number,
	frequencies: number[]
): number[] {
	if (bands.length === 0) return new Array(frequencies.length).fill(0);

	const allCoeffs = bands.map((b) => coefficients(b, sampleRate));
	return frequencies.map((freq) =>
		allCoeffs.reduce((total, c) => total + gainDB(c, freq, sampleRate), 0)
	);
}

/** Per-band frequency responses for ghost fills. */
export function perBandResponses(
	bands: EQBand[],
	sampleRate: number,
	frequencies: number[]
): number[][] {
	return bands.map((band) => {
		const c = coefficients(band, sampleRate);
		return frequencies.map((freq) => gainDB(c, freq, sampleRate));
	});
}
