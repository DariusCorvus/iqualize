use crate::dsp::biquad::EQBand;
use crate::state::persistence::EQPresetData;
use uuid::Uuid;

// Stable UUIDs matching macOS version for cross-platform preset compatibility
pub const FLAT_ID: Uuid = Uuid::from_bytes([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]);

const DEFAULT_FREQS: [f32; 10] = [32.0, 64.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0];

fn make_preset(id_byte: u8, name: &str, gains: &[f32]) -> EQPresetData {
    let bands: Vec<EQBand> = DEFAULT_FREQS
        .iter()
        .zip(gains.iter())
        .map(|(&freq, &gain)| EQBand::new(freq, gain))
        .collect();
    EQPresetData {
        id: Uuid::from_bytes([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, id_byte]),
        name: name.to_string(),
        bands,
        right_bands: None,
        is_built_in: true,
    }
}

pub fn built_in_presets() -> Vec<EQPresetData> {
    vec![
        // Flat
        make_preset(1, "Flat", &[0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]),
        // Bass Boost
        make_preset(2, "Bass Boost", &[10.0, 10.0, 8.0, 4.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]),
        // Vocal Clarity
        make_preset(3, "Vocal Clarity", &[-6.0, -6.0, -4.0, 0.0, 0.0, 6.0, 6.0, 4.0, 0.0, 0.0]),
        // Loudness
        make_preset(4, "Loudness", &[8.0, 6.0, 0.0, -2.0, -4.0, -2.0, 0.0, 2.0, 4.0, 6.0]),
        // Treble Boost
        make_preset(5, "Treble Boost", &[0.0, 0.0, 0.0, 0.0, 0.0, 2.0, 4.0, 6.0, 8.0, 10.0]),
        // Podcast
        make_preset(6, "Podcast", &[-8.0, -4.0, -2.0, 0.0, 2.0, 4.0, 6.0, 4.0, 2.0, 0.0]),
        // Techno
        make_preset(7, "Techno", &[8.0, 8.0, 4.0, -2.0, -4.0, -2.0, 0.0, 4.0, 6.0, 8.0]),
        // Deep House
        make_preset(8, "Deep House", &[6.0, 10.0, 8.0, 2.0, -2.0, -4.0, -2.0, 0.0, 2.0, 4.0]),
        // Hard Techno
        make_preset(9, "Hard Techno", &[10.0, 10.0, 6.0, 0.0, -4.0, -2.0, 2.0, 6.0, 8.0, 10.0]),
        // Minimal
        make_preset(0x0A, "Minimal", &[4.0, 6.0, 4.0, 0.0, -2.0, -2.0, 0.0, 2.0, 4.0, 2.0]),
        // American Rap
        make_preset(0x0B, "American Rap", &[10.0, 8.0, 4.0, 0.0, -2.0, -2.0, 2.0, 4.0, 6.0, 4.0]),
        // German Rap
        make_preset(0x0C, "German Rap", &[6.0, 8.0, 6.0, 2.0, -2.0, 0.0, 4.0, 4.0, 2.0, 2.0]),
        // Luzifer's Void (custom frequencies)
        EQPresetData {
            id: Uuid::from_bytes([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x0D]),
            name: "Luzifer's Void".to_string(),
            bands: vec![
                EQBand::new(18.0, 4.0).with_bandwidth(2.0),
                EQBand::new(32.0, 7.0).with_bandwidth(1.8),
                EQBand::new(55.0, 8.0).with_bandwidth(1.6),
                EQBand::new(85.0, 6.0).with_bandwidth(1.4),
                EQBand::new(130.0, 2.0).with_bandwidth(1.2),
                EQBand::new(220.0, -5.0).with_bandwidth(1.2),
                EQBand::new(500.0, -5.0).with_bandwidth(1.1),
                EQBand::new(1000.0, -4.0).with_bandwidth(1.0),
                EQBand::new(2000.0, -2.0).with_bandwidth(0.9),
                EQBand::new(3500.0, 1.0).with_bandwidth(0.8),
                EQBand::new(5000.0, 4.0).with_bandwidth(0.8),
                EQBand::new(7000.0, 5.0).with_bandwidth(0.6),
                EQBand::new(9500.0, 6.0).with_bandwidth(0.5),
                EQBand::new(12000.0, 5.0).with_bandwidth(0.6),
                EQBand::new(15500.0, 4.0).with_bandwidth(0.8),
                EQBand::new(19000.0, 3.0).with_bandwidth(1.0),
            ],
            right_bands: None,
            is_built_in: true,
        },
        // DEADBEEF
        EQPresetData {
            id: Uuid::from_bytes([0xDE, 0xAD, 0x00, 0x03, 0xBE, 0xEF, 0x4E, 0x87, 0xA5, 0x91, 0x00, 0x00, 0xDE, 0xAD, 0xBE, 0xEF]),
            name: "DEADBEEF".to_string(),
            bands: vec![
                EQBand::new(27.0, 7.0).with_bandwidth(1.8),
                EQBand::new(55.0, 8.0).with_bandwidth(1.6),
                EQBand::new(111.0, 5.0).with_bandwidth(1.4),
                EQBand::new(222.0, -6.0).with_bandwidth(1.2),
                EQBand::new(445.0, -8.0).with_bandwidth(1.4),
                EQBand::new(890.0, -6.0).with_bandwidth(1.2),
                EQBand::new(1781.0, 5.0).with_bandwidth(0.5),
                EQBand::new(3562.0, 7.0).with_bandwidth(0.4),
                EQBand::new(7125.0, 6.0).with_bandwidth(0.5),
                EQBand::new(14251.0, 4.0).with_bandwidth(0.7),
            ],
            right_bands: None,
            is_built_in: true,
        },
        // 0xDEADBEEF
        EQPresetData {
            id: Uuid::from_bytes([0xDE, 0xAD, 0x00, 0x04, 0xBE, 0xEF, 0x4E, 0x87, 0xA5, 0x91, 0x00, 0x00, 0xDE, 0xAD, 0xBE, 0xEF]),
            name: "0xDEADBEEF".to_string(),
            bands: vec![
                EQBand::new(27.0, 6.0).with_bandwidth(1.4),
                EQBand::new(23.0, -5.0).with_bandwidth(0.4),
                EQBand::new(55.0, 7.0).with_bandwidth(1.2),
                EQBand::new(47.0, -6.0).with_bandwidth(0.3),
                EQBand::new(111.0, 4.0).with_bandwidth(1.0),
                EQBand::new(95.0, -5.0).with_bandwidth(0.3),
                EQBand::new(222.0, -4.0).with_bandwidth(0.8),
                EQBand::new(190.0, -6.0).with_bandwidth(0.3),
                EQBand::new(445.0, -5.0).with_bandwidth(0.8),
                EQBand::new(381.0, -7.0).with_bandwidth(0.3),
                EQBand::new(890.0, -3.0).with_bandwidth(0.7),
                EQBand::new(763.0, -6.0).with_bandwidth(0.3),
                EQBand::new(1781.0, 3.0).with_bandwidth(0.5),
                EQBand::new(1527.0, -5.0).with_bandwidth(0.3),
                EQBand::new(3562.0, 5.0).with_bandwidth(0.4),
                EQBand::new(3054.0, -4.0).with_bandwidth(0.3),
                EQBand::new(7125.0, 4.0).with_bandwidth(0.4),
                EQBand::new(6109.0, -5.0).with_bandwidth(0.3),
                EQBand::new(14251.0, 3.0).with_bandwidth(0.6),
                EQBand::new(12219.0, -4.0).with_bandwidth(0.3),
            ],
            right_bands: None,
            is_built_in: true,
        },
    ]
}
