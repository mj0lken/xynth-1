import AppKit
import SwiftUI

/// Eight bold, unmistakably distinct industrial-design colorways for XYNTH-1:
/// from pure Dieter Rams white & OP-1 anodized aluminum to 1984 DX-style tech grey,
/// neon synthwave, carved Andean Inca gold, brutalist hypermodern acid, and warm Japanese clay.
enum XynthThemePreset: String, CaseIterable, Identifiable, Codable {
    case op1Field
    case tech80s
    case dieterWhite
    case obsidian
    case neonCyber
    case incaGold
    case acidModern
    case kotoClay

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .op1Field: return "OP-1 Field"
        case .tech80s: return "80s Tech"
        case .dieterWhite: return "Dieter White"
        case .obsidian: return "Obsidian"
        case .neonCyber: return "Neon Cyber"
        case .incaGold: return "Inca Gold"
        case .acidModern: return "Acid Modern"
        case .kotoClay: return "Koto Clay"
        }
    }

    var shortCode: String {
        switch self {
        case .op1Field: return "OP1"
        case .tech80s: return "80S"
        case .dieterWhite: return "WHT"
        case .obsidian: return "OBS"
        case .neonCyber: return "NEO"
        case .incaGold: return "INC"
        case .acidModern: return "ACD"
        case .kotoClay: return "KTO"
        }
    }

    var badgeText: String {
        switch self {
        case .op1Field: return "FIELD // 5V HAPTIC"
        case .tech80s: return "DX-84 // DIGITAL FM"
        case .dieterWhite: return "MOD.01 // BRAUN LAB"
        case .obsidian: return "PRO MKII // STEALTH"
        case .neonCyber: return "TOKYO '89 // HYPER"
        case .incaGold: return "INTI-01 // TEMPLE"
        case .acidModern: return "SYS.30 // BRUTALIST"
        case .kotoClay: return "KYOTO // CERAMIC"
        }
    }

    var tagline: String {
        switch self {
        case .op1Field: return "Brushed Nordic aluminum, speaker grille matrix & bold primary encoders"
        case .tech80s: return "1984 industrial grey steel with retro racing stripes & CRT green OLED"
        case .dieterWhite: return "Gallery snow-white matte chassis with Braun vermilion signal stripe"
        case .obsidian: return "Anodized matte-black rack steel with phosphor cyan & violet underglow"
        case .neonCyber: return "Electric ultraviolet deck with glowing magenta-cyan neon tubes"
        case .incaGold: return "Volcanic basalt stone with 24k stepped gold fretwork & turquoise inlay"
        case .acidModern: return "Raw dark titanium with searing electric chartreuse hazard stripes"
        case .kotoClay: return "Warm Japanese ceramic clay with persimmon hanko seal & indigo ink"
        }
    }

    var palette: XynthPalette {
        switch self {
        case .op1Field:
            return XynthPalette(
                preset: self,
                isLightChassis: true,
                chassisTop: Color(hex: 0xF1F3EE),
                chassisBottom: Color(hex: 0xDCDFD8),
                moduleBg: Color(hex: 0xE6E9E3),
                moduleBorder: Color.black.opacity(0.13),
                keycapBg: Color(hex: 0xFAFBF8),
                keycapPressedBg: Color(hex: 0xD8DCD3),
                keycapActiveBg: Color(hex: 0x16191E),
                keycapBorder: Color.black.opacity(0.16),
                keycapShadow: Color.black.opacity(0.15),
                oledBg: Color(hex: 0x090B0E),
                oledBorder: Color(hex: 0x252A32),
                padBgTop: Color(hex: 0x14171D),
                padBgBottom: Color(hex: 0x0B0D12),
                inkPrimary: Color(hex: 0x14171C),
                inkSecondary: Color(hex: 0x434A54),
                inkMuted: Color(hex: 0x707884),
                oledInkPrimary: Color(hex: 0xF7F9FC),
                oledInkMuted: Color(hex: 0x8A94A6),
                ledOff: Color(hex: 0xABB2BC),
                enc1: Color(hex: 0x00B4DB), // Electric Cyan
                enc2: Color(hex: 0xF0A500), // Ochre Gold
                enc3: Color(hex: 0xFF4F17), // Signal Tangerine
                enc4: Color(hex: 0x2260FF), // Cobalt Blue
                enc5: Color(hex: 0x00C484), // Mint
                ledAlert: Color(hex: 0xFF3E29),
                ledGood: Color(hex: 0x00C484),
                stripeColors: [Color(hex: 0x00B4DB), Color(hex: 0xF0A500), Color(hex: 0xFF4F17), Color(hex: 0x2260FF)],
                chassisGlow: Color(hex: 0x00B4DB).opacity(0.10),
                ferroCore: Color(hex: 0x07090D),
                ferroSpecular: Color(hex: 0xE9F9FF),
                ferroRim: Color(hex: 0x00C4EB),
                ferroField: Color(hex: 0x2260FF),
                dropdownBg: Color(hex: 0x14181F),
                dropdownBorder: Color(hex: 0x00B4DB).opacity(0.50),
                windowNSColor: NSColor(red: 0.90, green: 0.91, blue: 0.88, alpha: 1.0),
                hasIncaTrim: false,
                hasRetroGrid: false,
                hasSpeakerGrille: true,
                hasNeonTube: false,
                hasHazardStripe: false,
                hasWashiGrain: false
            )

        case .tech80s:
            return XynthPalette(
                preset: self,
                isLightChassis: true,
                chassisTop: Color(hex: 0xC8C4B8),
                chassisBottom: Color(hex: 0xABA79B),
                moduleBg: Color(hex: 0xBDB9AD),
                moduleBorder: Color.black.opacity(0.26),
                keycapBg: Color(hex: 0x2C2F35),
                keycapPressedBg: Color(hex: 0x1E2025),
                keycapActiveBg: Color(hex: 0x14171B),
                keycapBorder: Color.black.opacity(0.55),
                keycapShadow: Color.black.opacity(0.32),
                oledBg: Color(hex: 0x05120A),
                oledBorder: Color(hex: 0x23262B),
                padBgTop: Color(hex: 0x171D1B),
                padBgBottom: Color(hex: 0x0D1210),
                inkPrimary: Color(hex: 0x181A1D),
                inkSecondary: Color(hex: 0x34373B),
                inkMuted: Color(hex: 0x52555A),
                oledInkPrimary: Color(hex: 0x4BFF8F),
                oledInkMuted: Color(hex: 0x2E8C54),
                ledOff: Color(hex: 0x53565C),
                enc1: Color(hex: 0x2CE65D), // CRT Phosphor Green
                enc2: Color(hex: 0xFF9800), // Vintage Amber
                enc3: Color(hex: 0xFF2D20), // Cassette Red
                enc4: Color(hex: 0x00C2B8), // DX7 Teal
                enc5: Color(hex: 0xFFD426), // Warm Yellow
                ledAlert: Color(hex: 0xFF2D20),
                ledGood: Color(hex: 0x2CE65D),
                stripeColors: [Color(hex: 0x00A89E), Color(hex: 0xFF9800), Color(hex: 0xE82A1E)],
                chassisGlow: Color(hex: 0x2CE65D).opacity(0.12),
                ferroCore: Color(hex: 0x050E09),
                ferroSpecular: Color(hex: 0xC4FFD9),
                ferroRim: Color(hex: 0x2CE65D),
                ferroField: Color(hex: 0xFF9800),
                dropdownBg: Color(hex: 0x1D2024),
                dropdownBorder: Color(hex: 0x2CE65D).opacity(0.55),
                windowNSColor: NSColor(red: 0.74, green: 0.72, blue: 0.67, alpha: 1.0),
                hasIncaTrim: false,
                hasRetroGrid: true,
                hasSpeakerGrille: false,
                hasNeonTube: false,
                hasHazardStripe: false,
                hasWashiGrain: false,
                darkKeycapsOnLightChassis: true
            )

        case .dieterWhite:
            return XynthPalette(
                preset: self,
                isLightChassis: true,
                chassisTop: Color(hex: 0xFFFFFF),
                chassisBottom: Color(hex: 0xF0F0EB),
                moduleBg: Color(hex: 0xF6F6F2),
                moduleBorder: Color.black.opacity(0.12),
                keycapBg: Color(hex: 0xFFFFFF),
                keycapPressedBg: Color(hex: 0xE5E5DF),
                keycapActiveBg: Color(hex: 0x16171A),
                keycapBorder: Color.black.opacity(0.15),
                keycapShadow: Color.black.opacity(0.10),
                oledBg: Color(hex: 0x0E0F12),
                oledBorder: Color(hex: 0x24262B),
                padBgTop: Color(hex: 0x181A1E),
                padBgBottom: Color(hex: 0x0F1013),
                inkPrimary: Color(hex: 0x111214),
                inkSecondary: Color(hex: 0x4E5158),
                inkMuted: Color(hex: 0x82868E),
                oledInkPrimary: Color(hex: 0xFAFBF8),
                oledInkMuted: Color(hex: 0x8B8F98),
                ledOff: Color(hex: 0xC9CCD1),
                enc1: Color(hex: 0xFF3D00), // Iconic Braun Vermilion
                enc2: Color(hex: 0x4A8522), // Braun Functional Olive
                enc3: Color(hex: 0xF2B100), // Signal Ochre
                enc4: Color(hex: 0x1F5CC9), // Precision Blueprint
                enc5: Color(hex: 0x202226), // Matte Carbon
                ledAlert: Color(hex: 0xFF3D00),
                ledGood: Color(hex: 0x4A8522),
                stripeColors: [Color(hex: 0xFF3D00), Color(hex: 0x111214)],
                chassisGlow: Color(hex: 0xFF3D00).opacity(0.08),
                ferroCore: Color(hex: 0x0A0B0E),
                ferroSpecular: Color(hex: 0xFFFFFF),
                ferroRim: Color(hex: 0xFF450A),
                ferroField: Color(hex: 0x8C929E),
                dropdownBg: Color(hex: 0x141518),
                dropdownBorder: Color(hex: 0xFF3D00).opacity(0.65),
                windowNSColor: NSColor(red: 0.98, green: 0.98, blue: 0.96, alpha: 1.0),
                hasIncaTrim: false,
                hasRetroGrid: false,
                hasSpeakerGrille: true,
                hasNeonTube: false,
                hasHazardStripe: false,
                hasWashiGrain: false
            )

        case .obsidian:
            return XynthPalette(
                preset: self,
                isLightChassis: false,
                chassisTop: Color(hex: 0x11161F),
                chassisBottom: Color(hex: 0x07090D),
                moduleBg: Color(hex: 0x131924),
                moduleBorder: Color(hex: 0x38F2C6).opacity(0.18),
                keycapBg: Color(hex: 0x1B2230),
                keycapPressedBg: Color(hex: 0x10151E),
                keycapActiveBg: Color(hex: 0x1D2B38),
                keycapBorder: Color.white.opacity(0.13),
                keycapShadow: Color.black.opacity(0.60),
                oledBg: Color(hex: 0x05070B),
                oledBorder: Color(hex: 0x38F2C6).opacity(0.32),
                padBgTop: Color(hex: 0x0A1019),
                padBgBottom: Color(hex: 0x05070C),
                inkPrimary: Color(hex: 0xF3F7FC),
                inkSecondary: Color(hex: 0x99A7BA),
                inkMuted: Color(hex: 0x616E82),
                oledInkPrimary: Color(hex: 0xF3F7FC),
                oledInkMuted: Color(hex: 0x6F7E94),
                ledOff: Color(hex: 0x2C3545),
                enc1: Color(hex: 0x2BF7CA), // Phosphor Cyan
                enc2: Color(hex: 0xFFB838), // Studio Amber
                enc3: Color(hex: 0x3FA9FF), // Electric Sky
                enc4: Color(hex: 0xA87AFF), // Deep Violet
                enc5: Color(hex: 0xFF4F72), // Neon Coral
                ledAlert: Color(hex: 0xFF4F72),
                ledGood: Color(hex: 0x2BF7CA),
                stripeColors: [Color(hex: 0x2BF7CA), Color(hex: 0x3FA9FF), Color(hex: 0xA87AFF)],
                chassisGlow: Color(hex: 0x2BF7CA).opacity(0.18),
                ferroCore: Color(hex: 0x03060A),
                ferroSpecular: Color(hex: 0xCCFFF4),
                ferroRim: Color(hex: 0x2BF7CA),
                ferroField: Color(hex: 0xA87AFF),
                dropdownBg: Color(hex: 0x0D121A),
                dropdownBorder: Color(hex: 0x2BF7CA).opacity(0.55),
                windowNSColor: NSColor(red: 0.045, green: 0.058, blue: 0.082, alpha: 1.0),
                hasIncaTrim: false,
                hasRetroGrid: false,
                hasSpeakerGrille: false,
                hasNeonTube: false,
                hasHazardStripe: false,
                hasWashiGrain: false
            )

        case .neonCyber:
            return XynthPalette(
                preset: self,
                isLightChassis: false,
                chassisTop: Color(hex: 0x16072E),
                chassisBottom: Color(hex: 0x080214),
                moduleBg: Color(hex: 0x1D0A3B).opacity(0.92),
                moduleBorder: Color(hex: 0xFF2498).opacity(0.48),
                keycapBg: Color(hex: 0x270E4F),
                keycapPressedBg: Color(hex: 0x170730),
                keycapActiveBg: Color(hex: 0x3E117A),
                keycapBorder: Color(hex: 0x00F6FF).opacity(0.45),
                keycapShadow: Color(hex: 0xFF2498).opacity(0.28),
                oledBg: Color(hex: 0x050111),
                oledBorder: Color(hex: 0x00F6FF).opacity(0.65),
                padBgTop: Color(hex: 0x14042C),
                padBgBottom: Color(hex: 0x070114),
                inkPrimary: Color(hex: 0xFFF2FF),
                inkSecondary: Color(hex: 0xD3B4FF),
                inkMuted: Color(hex: 0x9167C9),
                oledInkPrimary: Color(hex: 0x00F6FF),
                oledInkMuted: Color(hex: 0xFF42B3),
                ledOff: Color(hex: 0x401E70),
                enc1: Color(hex: 0x00F6FF), // Laser Cyan
                enc2: Color(hex: 0xFF2498), // Hot Magenta
                enc3: Color(hex: 0xB4FF00), // Cyber Lime
                enc4: Color(hex: 0xFFE600), // High-Voltage Yellow
                enc5: Color(hex: 0xC46BFF), // Ultraviolet
                ledAlert: Color(hex: 0xFF2498),
                ledGood: Color(hex: 0xB4FF00),
                stripeColors: [Color(hex: 0xFF2498), Color(hex: 0x9E47FF), Color(hex: 0x00F6FF)],
                chassisGlow: Color(hex: 0xFF2498).opacity(0.32),
                ferroCore: Color(hex: 0x080214),
                ferroSpecular: Color(hex: 0xE6FFFF),
                ferroRim: Color(hex: 0xFF2498),
                ferroField: Color(hex: 0x00F6FF),
                dropdownBg: Color(hex: 0x120526),
                dropdownBorder: Color(hex: 0xFF2498).opacity(0.80),
                windowNSColor: NSColor(red: 0.06, green: 0.02, blue: 0.14, alpha: 1.0),
                hasIncaTrim: false,
                hasRetroGrid: true,
                hasSpeakerGrille: false,
                hasNeonTube: true,
                hasHazardStripe: false,
                hasWashiGrain: false
            )

        case .incaGold:
            return XynthPalette(
                preset: self,
                isLightChassis: false,
                chassisTop: Color(hex: 0x261A12),
                chassisBottom: Color(hex: 0x120B07),
                moduleBg: Color(hex: 0x2C1E15),
                moduleBorder: Color(hex: 0xF7BC26).opacity(0.45),
                keycapBg: Color(hex: 0x38261B),
                keycapPressedBg: Color(hex: 0x21150E),
                keycapActiveBg: Color(hex: 0x4E341D),
                keycapBorder: Color(hex: 0xF7BC26).opacity(0.55),
                keycapShadow: Color.black.opacity(0.65),
                oledBg: Color(hex: 0x0E0905),
                oledBorder: Color(hex: 0xF7BC26).opacity(0.75),
                padBgTop: Color(hex: 0x1E140D),
                padBgBottom: Color(hex: 0x0E0905),
                inkPrimary: Color(hex: 0xFFF2D6),
                inkSecondary: Color(hex: 0xD9BE8F),
                inkMuted: Color(hex: 0xA18358),
                oledInkPrimary: Color(hex: 0xFFD04A),
                oledInkMuted: Color(hex: 0x24D8C6),
                ledOff: Color(hex: 0x543E29),
                enc1: Color(hex: 0xFFBF24), // 24k Sun Gold
                enc2: Color(hex: 0x1EE3CE), // Andean Turquoise
                enc3: Color(hex: 0xF04E26), // Terracotta Vermilion
                enc4: Color(hex: 0x5AD66B), // Temple Jade
                enc5: Color(hex: 0xFF8C24), // Molten Copper
                ledAlert: Color(hex: 0xF04E26),
                ledGood: Color(hex: 0x1EE3CE),
                stripeColors: [Color(hex: 0xFFBF24), Color(hex: 0x1EE3CE), Color(hex: 0xF04E26)],
                chassisGlow: Color(hex: 0xFFBF24).opacity(0.24),
                ferroCore: Color(hex: 0x140C05),
                ferroSpecular: Color(hex: 0xFFF3BF),
                ferroRim: Color(hex: 0xFFBF24),
                ferroField: Color(hex: 0x1EE3CE),
                dropdownBg: Color(hex: 0x1A110B),
                dropdownBorder: Color(hex: 0xFFBF24).opacity(0.75),
                windowNSColor: NSColor(red: 0.11, green: 0.075, blue: 0.05, alpha: 1.0),
                hasIncaTrim: true,
                hasRetroGrid: false,
                hasSpeakerGrille: false,
                hasNeonTube: false,
                hasHazardStripe: false,
                hasWashiGrain: false
            )

        case .acidModern:
            return XynthPalette(
                preset: self,
                isLightChassis: false,
                chassisTop: Color(hex: 0x171B20),
                chassisBottom: Color(hex: 0x0C0F13),
                moduleBg: Color(hex: 0x1B2027),
                moduleBorder: Color(hex: 0xDCFF00).opacity(0.32),
                keycapBg: Color(hex: 0x232933),
                keycapPressedBg: Color(hex: 0x14181F),
                keycapActiveBg: Color(hex: 0x2B333E),
                keycapBorder: Color.white.opacity(0.20),
                keycapShadow: Color.black.opacity(0.55),
                oledBg: Color(hex: 0x07090C),
                oledBorder: Color(hex: 0xDCFF00).opacity(0.65),
                padBgTop: Color(hex: 0x0F1218),
                padBgBottom: Color(hex: 0x07090C),
                inkPrimary: Color(hex: 0xF7FAFC),
                inkSecondary: Color(hex: 0xB2BECB),
                inkMuted: Color(hex: 0x73808F),
                oledInkPrimary: Color(hex: 0xDCFF00),
                oledInkMuted: Color(hex: 0x62CFFF),
                ledOff: Color(hex: 0x3B4552),
                enc1: Color(hex: 0xDCFF00), // Searing Acid Chartreuse
                enc2: Color(hex: 0x3B7BFF), // Hyper Cobalt
                enc3: Color(hex: 0xFF4713), // Hazard Orange
                enc4: Color(hex: 0x5CE6FF), // Glacial Cyan
                enc5: Color(hex: 0xF7FAFC), // Pure White
                ledAlert: Color(hex: 0xFF4713),
                ledGood: Color(hex: 0xDCFF00),
                stripeColors: [Color(hex: 0xDCFF00), Color(hex: 0x3B7BFF), Color(hex: 0xFF4713)],
                chassisGlow: Color(hex: 0xDCFF00).opacity(0.22),
                ferroCore: Color(hex: 0x080A0D),
                ferroSpecular: Color(hex: 0xF4FFAB),
                ferroRim: Color(hex: 0xDCFF00),
                ferroField: Color(hex: 0x3B7BFF),
                dropdownBg: Color(hex: 0x10141A),
                dropdownBorder: Color(hex: 0xDCFF00).opacity(0.75),
                windowNSColor: NSColor(red: 0.075, green: 0.090, blue: 0.108, alpha: 1.0),
                hasIncaTrim: false,
                hasRetroGrid: false,
                hasSpeakerGrille: false,
                hasNeonTube: false,
                hasHazardStripe: true,
                hasWashiGrain: false
            )

        case .kotoClay:
            return XynthPalette(
                preset: self,
                isLightChassis: true,
                chassisTop: Color(hex: 0xF2E8DC),
                chassisBottom: Color(hex: 0xDFD0BE),
                moduleBg: Color(hex: 0xE8DBCB),
                moduleBorder: Color(hex: 0x2D2638).opacity(0.18),
                keycapBg: Color(hex: 0xF9F2E8),
                keycapPressedBg: Color(hex: 0xD7C6B2),
                keycapActiveBg: Color(hex: 0x1D243C),
                keycapBorder: Color(hex: 0x2D2638).opacity(0.22),
                keycapShadow: Color(hex: 0x2D2638).opacity(0.16),
                oledBg: Color(hex: 0x121624),
                oledBorder: Color(hex: 0x2D2638).opacity(0.38),
                padBgTop: Color(hex: 0x1A2033),
                padBgBottom: Color(hex: 0x101422),
                inkPrimary: Color(hex: 0x1B2034),
                inkSecondary: Color(hex: 0x4E4A59),
                inkMuted: Color(hex: 0x7D736B),
                oledInkPrimary: Color(hex: 0xFAF0E2),
                oledInkMuted: Color(hex: 0xF06848),
                ledOff: Color(hex: 0xB8A896),
                enc1: Color(hex: 0xEB4E2D), // Hanko Persimmon Vermilion
                enc2: Color(hex: 0x1E8F6E), // Matcha Jade
                enc3: Color(hex: 0x264B9E), // Aizome Indigo
                enc4: Color(hex: 0xE09C14), // Yuzu Gold
                enc5: Color(hex: 0xB83D72), // Ume Plum
                ledAlert: Color(hex: 0xEB4E2D),
                ledGood: Color(hex: 0x1E8F6E),
                stripeColors: [Color(hex: 0xEB4E2D), Color(hex: 0x264B9E), Color(hex: 0x1E8F6E)],
                chassisGlow: Color(hex: 0xEB4E2D).opacity(0.12),
                ferroCore: Color(hex: 0x101422),
                ferroSpecular: Color(hex: 0xFFE5D4),
                ferroRim: Color(hex: 0xEB4E2D),
                ferroField: Color(hex: 0x1E8F6E),
                dropdownBg: Color(hex: 0x181E30),
                dropdownBorder: Color(hex: 0xEB4E2D).opacity(0.65),
                windowNSColor: NSColor(red: 0.92, green: 0.87, blue: 0.81, alpha: 1.0),
                hasIncaTrim: false,
                hasRetroGrid: false,
                hasSpeakerGrille: false,
                hasNeonTube: false,
                hasHazardStripe: false,
                hasWashiGrain: true
            )
        }
    }
}

struct XynthPalette {
    let preset: XynthThemePreset
    let isLightChassis: Bool
    let chassisTop: Color
    let chassisBottom: Color
    let moduleBg: Color
    let moduleBorder: Color
    let keycapBg: Color
    let keycapPressedBg: Color
    let keycapActiveBg: Color
    let keycapBorder: Color
    let keycapShadow: Color
    let oledBg: Color
    let oledBorder: Color
    let padBgTop: Color
    let padBgBottom: Color
    let inkPrimary: Color
    let inkSecondary: Color
    let inkMuted: Color
    let oledInkPrimary: Color
    let oledInkMuted: Color
    let ledOff: Color
    let enc1: Color
    let enc2: Color
    let enc3: Color
    let enc4: Color
    let enc5: Color
    let ledAlert: Color
    let ledGood: Color
    let stripeColors: [Color]
    let chassisGlow: Color
    let ferroCore: Color
    let ferroSpecular: Color
    let ferroRim: Color
    let ferroField: Color
    let dropdownBg: Color
    let dropdownBorder: Color
    let windowNSColor: NSColor
    let hasIncaTrim: Bool
    let hasRetroGrid: Bool
    let hasSpeakerGrille: Bool
    let hasNeonTube: Bool
    let hasHazardStripe: Bool
    let hasWashiGrain: Bool
    var darkKeycapsOnLightChassis: Bool = false

    /// 5 distinct finger voice colors (`F1`–`F5`).
    var voicePalette: [Color] { [enc1, enc4, enc2, enc3, enc5] }

    func color(forVoiceIndex index: Int) -> Color {
        voicePalette[abs(index) % voicePalette.count]
    }

    var keycapInk: Color {
        if isLightChassis && !darkKeycapsOnLightChassis {
            return inkPrimary
        }
        return Color(white: 0.94)
    }

    var keycapMutedInk: Color {
        if isLightChassis && !darkKeycapsOnLightChassis {
            return inkMuted
        }
        return Color(white: 0.62)
    }

    var keycapActiveInk: Color {
        Color(white: 0.98)
    }

    var swatchColors: [Color] { [chassisTop, enc1, enc3] }

    var tooltipBg: Color { oledBg.opacity(0.97) }
    var tooltipBorder: Color { enc1.opacity(0.68) }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

struct HardwareModuleCard: ViewModifier {
    let palette: XynthPalette
    var cornerRadius: CGFloat = 12
    var accentBorder: Color? = nil

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(palette.moduleBg)
                    .shadow(color: palette.keycapShadow.opacity(0.45), radius: palette.hasNeonTube ? 7 : 2.5, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        accentBorder ?? palette.moduleBorder,
                        lineWidth: (accentBorder != nil || palette.hasNeonTube) ? 1.25 : 1.0
                    )
            )
    }
}

extension View {
    func hardwareModule(_ palette: XynthPalette, cornerRadius: CGFloat = 12, accentBorder: Color? = nil) -> some View {
        modifier(HardwareModuleCard(palette: palette, cornerRadius: cornerRadius, accentBorder: accentBorder))
    }
}
