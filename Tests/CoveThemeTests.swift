import XCTest
import SwiftUI
@testable import Cove

#if os(macOS)
    import AppKit

    /// The palette is built from dynamic colors that resolve themselves against
    /// the current appearance instead of being selected by a `ColorScheme` the
    /// views pass around. That only works if the resolution actually happens —
    /// a provider that silently returned one shade for both appearances would
    /// look correct in light mode and wrong in dark, with nothing failing.
    ///
    /// macOS-only because `performAsCurrentDrawingAppearance` is the one place a
    /// test can pin the appearance and read the result back.
    @MainActor
    final class CoveThemeTests: XCTestCase {

        private func resolved(_ color: Color, in appearanceName: NSAppearance.Name) -> NSColor {
            var resolvedColor = NSColor.clear
            let appearance = NSAppearance(named: appearanceName)!
            appearance.performAsCurrentDrawingAppearance {
                resolvedColor =
                    NSColor(color)
                    .usingColorSpace(.sRGB) ?? NSColor(color)
            }
            return resolvedColor
        }

        private func assertDiffersByAppearance(
            _ color: Color,
            _ label: String,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            let light = resolved(color, in: .aqua)
            let dark = resolved(color, in: .darkAqua)
            XCTAssertNotEqual(
                light, dark,
                "\(label) resolved to the same color in both appearances",
                file: file, line: line)
        }

        func testEveryPaletteTokenResolvesPerAppearance() {
            assertDiffersByAppearance(CoveTheme.canvas, "canvas")
            assertDiffersByAppearance(CoveTheme.surface, "surface")
            assertDiffersByAppearance(CoveTheme.ink, "ink")
            assertDiffersByAppearance(CoveTheme.accent, "accent")
            assertDiffersByAppearance(CoveTheme.moss, "moss")
            assertDiffersByAppearance(CoveTheme.alert, "alert")
            assertDiffersByAppearance(CoveTheme.hairline, "hairline")
            assertDiffersByAppearance(CoveTheme.field, "field")
            assertDiffersByAppearance(CoveTheme.fieldStroke, "fieldStroke")
        }

        /// A field is a well in light and a lift in dark, and the flip is the
        /// whole point of the token.
        ///
        /// It used to take `canvas` in both, which is right on paper — a well
        /// cut into the lighter surface — and wrong at night, where the canvas
        /// sits *below* the surface it is set into by so little that an empty
        /// capture field disappeared into the panel. Sinking it further would
        /// have run out of room; lifting it has all the room there is. What
        /// this pins is the direction in each appearance, since a token that
        /// quietly went back to sinking in dark would look plausible in a
        /// screenshot and fail the one reader it was changed for.
        func testFieldSinksOnPaperAndLiftsAtNight() {
            let lightField = relativeLuminance(resolved(CoveTheme.field, in: .aqua))
            let lightSurface = relativeLuminance(resolved(CoveTheme.surface, in: .aqua))
            XCTAssertLessThan(lightField, lightSurface, "field should sink into the light surface")

            let darkField = relativeLuminance(resolved(CoveTheme.field, in: .darkAqua))
            let darkSurface = relativeLuminance(resolved(CoveTheme.surface, in: .darkAqua))
            XCTAssertGreaterThan(darkField, darkSurface, "field should lift off the dark surface")
            // Lifting it by a hair would satisfy the direction and change
            // nothing on screen, so the dark step is held to the size the light
            // one already has — measured where luminance is compressed and a
            // small ratio is a large visible difference.
            XCTAssertGreaterThan(
                contrastRatio(
                    resolved(CoveTheme.field, in: .darkAqua),
                    resolved(CoveTheme.surface, in: .darkAqua)),
                contrastRatio(
                    resolved(CoveTheme.field, in: .aqua),
                    resolved(CoveTheme.surface, in: .aqua)),
                "the dark field should stand off its surface at least as far as the light one")
        }

        /// A field's edge is what says the control is there when nothing has
        /// been typed into it, so it is a step stronger than the hairline that
        /// separates two surfaces already telling themselves apart.
        func testFieldStrokeIsStrongerThanTheHairline() {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let stroke = resolved(CoveTheme.fieldStroke, in: appearance)
                let hairline = resolved(CoveTheme.hairline, in: appearance)
                XCTAssertGreaterThan(
                    stroke.alphaComponent, hairline.alphaComponent,
                    "field stroke against hairline in \(appearance.rawValue)")
            }
        }

        /// Whatever the field's fill is, what gets typed into it is the point.
        func testInkOnFieldClearsTheContrastFloorInBothAppearances() {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let ratio = contrastRatio(
                    resolved(CoveTheme.ink, in: appearance),
                    resolved(CoveTheme.field, in: appearance))
                XCTAssertGreaterThan(ratio, 7, "ink on field in \(appearance.rawValue)")
            }
        }

        /// The canvas is the page and the ink is what's written on it, so their
        /// contrast is the one ratio the whole palette rests on.
        func testInkOnCanvasClearsTheContrastFloorInBothAppearances() {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let ratio = contrastRatio(
                    resolved(CoveTheme.ink, in: appearance),
                    resolved(CoveTheme.canvas, in: appearance))
                XCTAssertGreaterThan(ratio, 7, "ink on canvas in \(appearance.rawValue)")
            }
        }

        /// The accent carries small text — due dates, counts, section counts —
        /// so it has to clear the 4.5:1 floor for normal-size text, not the 3:1
        /// one that would be enough if it only ever filled shapes.
        func testAccentOnCanvasClearsTheContrastFloorInBothAppearances() {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let ratio = contrastRatio(
                    resolved(CoveTheme.accent, in: appearance),
                    resolved(CoveTheme.canvas, in: appearance))
                XCTAssertGreaterThan(ratio, 4.5, "accent on canvas in \(appearance.rawValue)")
            }
        }

        func testAlertOnCanvasClearsTheContrastFloorInBothAppearances() {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let ratio = contrastRatio(
                    resolved(CoveTheme.alert, in: appearance),
                    resolved(CoveTheme.canvas, in: appearance))
                XCTAssertGreaterThan(ratio, 4.5, "alert on canvas in \(appearance.rawValue)")
            }
        }

        // MARK: - WCAG contrast

        private func contrastRatio(_ a: NSColor, _ b: NSColor) -> CGFloat {
            let lighter = max(relativeLuminance(a), relativeLuminance(b))
            let darker = min(relativeLuminance(a), relativeLuminance(b))
            return (lighter + 0.05) / (darker + 0.05)
        }

        private func relativeLuminance(_ color: NSColor) -> CGFloat {
            func linear(_ channel: CGFloat) -> CGFloat {
                channel <= 0.03928
                    ? channel / 12.92
                    : pow((channel + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(color.redComponent)
                + 0.7152 * linear(color.greenComponent)
                + 0.0722 * linear(color.blueComponent)
        }
    }
#endif
