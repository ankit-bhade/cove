import XCTest
import SwiftUI
@testable import Cove

#if os(macOS)
    import AppKit

    /// The Mac's dark icon is applied at runtime rather than from the catalog,
    /// because an `appiconset` has no dark `mac` slot — see `DockIcon`.
    ///
    /// That route fails quietly in a way the catalog route does not: if the
    /// imageset is renamed or dropped, `NSImage(named:)` returns nil, the Dock
    /// keeps whatever icon it already had, and the app looks entirely correct
    /// in light mode. Only a reader who switches to dark and looks at the Dock
    /// would notice, so the name is pinned here instead.
    @MainActor
    final class DockIconTests: XCTestCase {

        func testDarkDockIconLoadsFromTheAssetCatalog() throws {
            let image = try XCTUnwrap(
                NSImage(named: DockIcon.darkImageName),
                """
                No image named "\(DockIcon.darkImageName)" in the catalog. \
                The dark Mac icon is applied through NSImage(named:), which \
                returns nil silently — the Dock would simply keep the light \
                tile in dark mode.
                """
            )
            XCTAssertGreaterThan(image.size.width, 0)
            XCTAssertEqual(image.size.width, image.size.height, "the tile is square")
        }

        /// The dark tile has to be dark: a copy of the light artwork under the
        /// dark name would load, pass every other check, and change nothing
        /// the user can see.
        func testDarkDockIconIsDarkerThanTheLightAppIcon() throws {
            let dark = try XCTUnwrap(NSImage(named: DockIcon.darkImageName))
            let light = try XCTUnwrap(NSImage(named: "AppIcon"))
            XCTAssertLessThan(
                try meanLuminance(of: dark),
                try meanLuminance(of: light),
                "the dark Dock tile is not darker than the app's light icon"
            )
        }

        /// The swap itself, not just the artwork behind it. The test bundle
        /// runs inside the app host, so `NSApp` is the real application object
        /// and `apply` can be checked against it — which is as close to the
        /// Dock as an automated test reaches.
        ///
        /// The assertion is on how light or dark the resulting icon is rather
        /// than on which object it is: assigning nil hands the Dock back to
        /// the bundle's icon, but AppKit refills the property with that icon
        /// instead of leaving it nil, so `applicationIconImage` is never nil
        /// to read.
        func testApplyingDarkInstallsTheDarkTileAndLightRestoresTheLightOne() throws {
            let application = try XCTUnwrap(NSApp)
            let original = application.applicationIconImage
            defer { application.applicationIconImage = original }

            DockIcon.apply(.dark)
            let inDark = try meanLuminance(
                of: try XCTUnwrap(application.applicationIconImage)
            )

            DockIcon.apply(.light)
            let inLight = try meanLuminance(
                of: try XCTUnwrap(application.applicationIconImage)
            )

            XCTAssertLessThan(
                inDark,
                inLight,
                """
                the Dock icon did not get darker in dark and lighter again in \
                light — the appearance swap is not reaching NSApp
                """
            )
        }

        /// Mean luminance over the whole tile, which is dominated by its
        /// ground — warm paper in light, near-black in dark.
        private func meanLuminance(of image: NSImage) throws -> Double {
            var rect = CGRect(origin: .zero, size: image.size)
            let cgImage = try XCTUnwrap(
                image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
            )
            let side = 32
            var pixels = [UInt8](repeating: 0, count: side * side * 4)
            let context = try XCTUnwrap(
                CGContext(
                    data: &pixels,
                    width: side,
                    height: side,
                    bitsPerComponent: 8,
                    bytesPerRow: side * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            )
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

            var total = 0.0
            for pixel in stride(from: 0, to: pixels.count, by: 4) {
                total +=
                    0.2126 * Double(pixels[pixel])
                    + 0.7152 * Double(pixels[pixel + 1])
                    + 0.0722 * Double(pixels[pixel + 2])
            }
            return total / Double(side * side)
        }
    }
#endif
