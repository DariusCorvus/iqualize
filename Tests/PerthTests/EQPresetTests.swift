import XCTest
@testable import Perth

final class EQPresetTests: XCTestCase {

    func testAllPresetsHaveTenBands() {
        for preset in EQPreset.allCases {
            XCTAssertEqual(preset.bands.count, EQPreset.bandCount)
        }
    }

    func testFlatIsAllZero() {
        for gain in EQPreset.flat.bands {
            XCTAssertEqual(gain, 0.0)
        }
    }

    func testBassBoostOnlyBoostsLows() {
        let bands = EQPreset.bassBoost.bands
        XCTAssertGreaterThan(bands[0], 0)
        XCTAssertGreaterThan(bands[1], 0)
        XCTAssertGreaterThan(bands[2], 0)
        for i in 3..<10 {
            XCTAssertEqual(bands[i], 0.0)
        }
    }

    func testVocalClarityCutsLowsBoostsMids() {
        let bands = EQPreset.vocalClarity.bands
        XCTAssertLessThan(bands[0], 0)
        XCTAssertLessThan(bands[1], 0)
        XCTAssertLessThan(bands[2], 0)
        XCTAssertGreaterThan(bands[5], 0)
        XCTAssertGreaterThan(bands[6], 0)
        XCTAssertGreaterThan(bands[7], 0)
    }

    func testFrequenciesAscending() {
        let freqs = EQPreset.frequencies
        for i in 1..<freqs.count {
            XCTAssertGreaterThan(freqs[i], freqs[i - 1])
        }
    }

    func testGainsWithinRange() {
        for preset in EQPreset.allCases {
            for gain in preset.bands {
                XCTAssertGreaterThanOrEqual(gain, -12.0)
                XCTAssertLessThanOrEqual(gain, 12.0)
            }
        }
    }

    func testDisplayNamesNotEmpty() {
        for preset in EQPreset.allCases {
            XCTAssertFalse(preset.displayName.isEmpty)
        }
    }
}

final class PerthStateTests: XCTestCase {

    func testDefaultState() {
        let state = PerthState.defaultState
        XCTAssertFalse(state.isEnabled)
        XCTAssertEqual(state.selectedPreset, .flat)
    }

    func testCodableRoundTrip() throws {
        let original = PerthState(isEnabled: true, selectedPreset: .bassBoost)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PerthState.self, from: data)
        XCTAssertEqual(decoded.isEnabled, original.isEnabled)
        XCTAssertEqual(decoded.selectedPreset, original.selectedPreset)
    }
}
