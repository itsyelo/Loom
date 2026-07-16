import XCTest
import CoreText
import Foundation
@testable import Loom

// MARK: - Test Keys

enum TestKey: String, LoomKey {
    case avatar, name, body, time, actionBar

    var loomKeyValue: String { rawValue }
}

// Helper to create attributed strings without UIFont dependency.
// `lineSpacing`, `paragraphSpacing`, and `lockedLineHeight` are opt-in;
// when none are set the resulting attributed string has no paragraphStyle
// attribute, preserving the legacy behavior used by existing tests.
private func makeAttrString(
    _ text: String,
    fontSize: CGFloat,
    lineSpacing: CGFloat = 0,
    paragraphSpacing: CGFloat = 0,
    lockedLineHeight: CGFloat? = nil
) -> NSAttributedString {
    let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
    var attrs: [NSAttributedString.Key: Any] = [.font: font]
    if lineSpacing > 0 || paragraphSpacing > 0 || lockedLineHeight != nil {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = paragraphSpacing
        if let height = lockedLineHeight {
            style.minimumLineHeight = height
            style.maximumLineHeight = height
        }
        attrs[.paragraphStyle] = style
    }
    return NSAttributedString(string: text, attributes: attrs)
}

final class LoomTests: XCTestCase {

    // MARK: - Basic Layout

    func testFixedSizeNode() {
        // Fixed node inside a container keeps its set width
        let layout = LoomLayout(width: 375) {
            HStack {
                Fixed(width: 100, height: 50).key(TestKey.avatar)
            }
        }
        let result = layout.calculate()

        XCTAssertEqual(result.size.width, 375)
        XCTAssertEqual(result.size.height, 50)

        let frame = result.frame(for: TestKey.avatar)
        XCTAssertNotNil(frame)
        XCTAssertEqual(frame!.width, 100)
        XCTAssertEqual(frame!.height, 50)
    }

    func testVStackLayout() {
        let layout = LoomLayout(width: 375) {
            VStack {
                Fixed(width: 375, height: 40).key(TestKey.name)
                Fixed(width: 375, height: 60).key(TestKey.body)
            }
        }
        let result = layout.calculate()

        XCTAssertEqual(result.height, 100)

        let nameFrame = result.frame(for: TestKey.name)!
        let bodyFrame = result.frame(for: TestKey.body)!
        XCTAssertEqual(nameFrame.origin.y, 0)
        XCTAssertEqual(bodyFrame.origin.y, 40)
    }

    func testHStackLayout() {
        let layout = LoomLayout(width: 375) {
            HStack {
                Fixed(width: 40, height: 40).key(TestKey.avatar)
                Fixed(width: 100, height: 40).key(TestKey.name)
            }
        }
        let result = layout.calculate()

        let avatarFrame = result.frame(for: TestKey.avatar)!
        let nameFrame = result.frame(for: TestKey.name)!
        XCTAssertEqual(avatarFrame.origin.x, 0)
        XCTAssertEqual(nameFrame.origin.x, 40)
    }

    func testVStackWithSpacing() {
        let layout = LoomLayout(width: 375) {
            VStack(spacing: 10) {
                Fixed(width: 375, height: 30).key(TestKey.name)
                Fixed(width: 375, height: 30).key(TestKey.body)
            }
        }
        let result = layout.calculate()

        XCTAssertEqual(result.height, 70) // 30 + 10 + 30

        let bodyFrame = result.frame(for: TestKey.body)!
        XCTAssertEqual(bodyFrame.origin.y, 40) // 30 + 10
    }

    // MARK: - Padding

    func testContainerPadding() {
        let layout = LoomLayout(width: 375) {
            VStack {
                Fixed(width: 100, height: 40).key(TestKey.avatar)
            }.padding(12)
        }
        let result = layout.calculate()

        XCTAssertEqual(result.height, 64) // 12 + 40 + 12

        let avatarFrame = result.frame(for: TestKey.avatar)!
        XCTAssertEqual(avatarFrame.origin.x, 12)
        XCTAssertEqual(avatarFrame.origin.y, 12)
    }

    // MARK: - ZStack

    func testZStackOverlay() {
        let layout = LoomLayout(width: 100) {
            ZStack {
                Fixed(width: 40, height: 40).key(TestKey.avatar)
                Fixed(width: 16, height: 16).key(TestKey.name)
            }
        }
        let result = layout.calculate()

        let avatarFrame = result.frame(for: TestKey.avatar)!
        let badgeFrame = result.frame(for: TestKey.name)!

        // Both start at (0, 0) by default (topLeft alignment)
        XCTAssertEqual(avatarFrame.origin.x, 0)
        XCTAssertEqual(avatarFrame.origin.y, 0)
        XCTAssertEqual(avatarFrame.width, 40)
        XCTAssertEqual(badgeFrame.origin.x, 0)
        XCTAssertEqual(badgeFrame.origin.y, 0)
        XCTAssertEqual(badgeFrame.width, 16)
    }

    func testZStackBottomRight() {
        // ZStack as direct root (single child in LoomLayout)
        let layout = LoomLayout(width: 40) {
            ZStack(alignment: .bottomRight) {
                Fixed(width: 40, height: 40).key(TestKey.avatar)
                Fixed(width: 16, height: 16).key(TestKey.name)
            }
        }
        let result = layout.calculate()

        let avatarFrame = result.frame(for: TestKey.avatar)
        let badgeFrame = result.frame(for: TestKey.name)
        XCTAssertNotNil(avatarFrame, "Avatar frame should exist. All: \(result.allFrames)")
        XCTAssertNotNil(badgeFrame, "Badge frame should exist. All: \(result.allFrames)")
        // Badge at bottom-right: (40-16, 40-16) = (24, 24)
        XCTAssertEqual(badgeFrame!.origin.x, 24, accuracy: 1)
        XCTAssertEqual(badgeFrame!.origin.y, 24, accuracy: 1)
    }

    // MARK: - Leaf Padding

    func testLeafPaddingAutoWraps() {
        // Text with padding should produce the same key frame as
        // manually wrapping in a VStack with padding
        let attr = makeAttrString("Hello", fontSize: 16)

        let autoLayout = LoomLayout(width: 375) {
            VStack {
                Text(attr).padding(12).key(TestKey.body)
            }
        }
        let autoResult = autoLayout.calculate()

        let manualLayout = LoomLayout(width: 375) {
            VStack {
                VStack {
                    Text(attr).key(TestKey.body)
                }.padding(12)
            }
        }
        let manualResult = manualLayout.calculate()

        // Both should have the same key frame (content area, not padded area)
        let autoFrame = autoResult.frame(for: TestKey.body)!
        let manualFrame = manualResult.frame(for: TestKey.body)!

        XCTAssertEqual(autoFrame.origin.x, manualFrame.origin.x, accuracy: 1)
        XCTAssertEqual(autoFrame.origin.y, manualFrame.origin.y, accuracy: 1)
        XCTAssertEqual(autoFrame.width, manualFrame.width, accuracy: 1)
        XCTAssertEqual(autoFrame.height, manualFrame.height, accuracy: 1)

        // Key frame should be inset from origin (not at 0,0)
        XCTAssertGreaterThanOrEqual(autoFrame.origin.x, 12)
        XCTAssertGreaterThanOrEqual(autoFrame.origin.y, 12)

        // Total height should include padding
        XCTAssertGreaterThan(autoResult.height, autoFrame.height + 20)
    }

    func testLeafWithoutPaddingUnchanged() {
        // Leaf without padding should behave exactly as before
        let attr = makeAttrString("No padding", fontSize: 16)
        let layout = LoomLayout(width: 375) {
            VStack {
                Text(attr).key(TestKey.name)
            }
        }
        let result = layout.calculate()
        let frame = result.frame(for: TestKey.name)!
        XCTAssertEqual(frame.origin.x, 0, accuracy: 1)
        XCTAssertEqual(frame.origin.y, 0, accuracy: 1)
    }

    // MARK: - Flex

    func testFlexGrow() {
        let layout = LoomLayout(width: 375) {
            HStack {
                Fixed(width: 40, height: 40).key(TestKey.avatar)
                Fixed(width: 0, height: 40).key(TestKey.name).flex(grow: 1)
            }
        }
        let result = layout.calculate()

        let nameFrame = result.frame(for: TestKey.name)!
        XCTAssertEqual(nameFrame.width, 335) // 375 - 40
    }

    // MARK: - Text Measurement

    func testTextNode() {
        let attr = makeAttrString("Hello, World!", fontSize: 16)
        let layout = LoomLayout(width: 375) {
            Text(attr).key(TestKey.name)
        }
        let result = layout.calculate()

        let frame = result.frame(for: TestKey.name)!
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
        XCTAssertLessThan(frame.height, 30)
    }

    func testMultilineText() {
        let longText = String(repeating: "This is a long text. ", count: 20)
        let attr = makeAttrString(longText, fontSize: 16)
        let layout = LoomLayout(width: 200) {
            Text(attr).key(TestKey.body)
        }
        let result = layout.calculate()

        let frame = result.frame(for: TestKey.body)!
        XCTAssertGreaterThan(frame.height, 30)
        XCTAssertLessThanOrEqual(frame.width, 200)
    }

    // MARK: - issue-01 regression: precise multi-line measurement

    func testMeasurerIncludesLineSpacing() {
        // Same text rendered with vs without paragraphStyle.lineSpacing —
        // measurer must reflect the difference. Without it, a Text node
        // bound to a UILabel that DOES honor lineSpacing renders past its
        // measured frame (or clips), producing the original "body text
        // jump on expand" symptom from issue-01.
        let longText = String(repeating: "This is a long text. ", count: 20)
        let bare = makeAttrString(longText, fontSize: 16)
        let spaced = makeAttrString(longText, fontSize: 16, lineSpacing: 4)

        let bareSize = TextMeasurer.measure(
            bare, maxWidth: 200, maxHeight: .greatestFiniteMagnitude
        )
        let spacedSize = TextMeasurer.measure(
            spaced, maxWidth: 200, maxHeight: .greatestFiniteMagnitude
        )

        // 16pt Helvetica wraps to many lines at 200pt; each gap adds 4pt.
        XCTAssertGreaterThan(spacedSize.height, bareSize.height + 4)
    }

    func testMeasurerIncludesParagraphSpacing() {
        // Two paragraphs separated by \n\n: paragraphSpacing must contribute
        // an inter-paragraph gap to the measured height.
        let twoPara = "Hello world.\n\nGoodbye world."
        let bare = makeAttrString(twoPara, fontSize: 16)
        let withParaSpacing = makeAttrString(twoPara, fontSize: 16, paragraphSpacing: 8)

        let bareSize = TextMeasurer.measure(
            bare, maxWidth: 200, maxHeight: .greatestFiniteMagnitude
        )
        let spacedSize = TextMeasurer.measure(
            withParaSpacing, maxWidth: 200, maxHeight: .greatestFiniteMagnitude
        )

        XCTAssertGreaterThan(spacedSize.height, bareSize.height)
    }

    func testTextMaxLinesClampsToExactNLineHeight() {
        let longText = String(repeating: "This is a long text. ", count: 20)
        let attr = makeAttrString(longText, fontSize: 16, lineSpacing: 4)

        let unlimited = TextMeasurer.measure(
            attr, maxWidth: 200, maxHeight: .greatestFiniteMagnitude, maxLines: 0
        )
        let oneLine = TextMeasurer.measure(
            attr, maxWidth: 200, maxHeight: .greatestFiniteMagnitude, maxLines: 1
        )
        let twoLines = TextMeasurer.measure(
            attr, maxWidth: 200, maxHeight: .greatestFiniteMagnitude, maxLines: 2
        )

        XCTAssertGreaterThan(unlimited.height, twoLines.height)
        XCTAssertGreaterThan(twoLines.height, oneLine.height)

        // Two lines ≈ 2 × oneLine + 1 × lineSpacing (4pt). Allow ceil slack.
        XCTAssertEqual(twoLines.height, oneLine.height * 2 + 4, accuracy: 4)
    }

    func testTextMaxLinesReportsActualWhenShorter() {
        // Short single-line text: maxLines=5 must NOT pad the height to 5
        // lines. Returned size matches the unconstrained measurement.
        let attr = makeAttrString("Short.", fontSize: 16)

        let natural = TextMeasurer.measure(
            attr, maxWidth: 200, maxHeight: .greatestFiniteMagnitude, maxLines: 0
        )
        let capped = TextMeasurer.measure(
            attr, maxWidth: 200, maxHeight: .greatestFiniteMagnitude, maxLines: 5
        )

        XCTAssertEqual(natural.height, capped.height)
    }

    func testTextMaxLinesInLayoutMatchesMeasurer() {
        // Guards the "text jumps on expand" bug from issue-01: the height
        // Loom assigns to a Text(attr, maxLines: 2) keyframe must equal the
        // height a direct TextMeasurer.measure(...) call returns for the
        // same arguments. Any drift here would mean Yoga is reinterpreting
        // the measure-func result and bound UILabels would render with
        // unexpected vertical insets between collapsed and expanded states.
        let longText = String(repeating: "This is a long text. ", count: 20)
        let attr = makeAttrString(longText, fontSize: 16, lineSpacing: 4)

        let layoutHeight = LoomLayout(width: 200) {
            Text(attr, maxLines: 2).key(TestKey.body)
        }.calculate().frame(for: TestKey.body)!.height

        let measuredHeight = TextMeasurer.measure(
            attr, maxWidth: 200, maxHeight: .greatestFiniteMagnitude, maxLines: 2
        ).height

        XCTAssertEqual(layoutHeight, measuredHeight, accuracy: 0.5)
    }

    func testLockedLineHeightProducesUniformLines() {
        // The canonical issue-01 user convention: setting
        // paragraphStyle.minimumLineHeight == maximumLineHeight forces every
        // line frame to exactly X. The measurer must reflect this exactly,
        // because the entire purpose of locking line height is to make the
        // bound UILabel render with deterministic baseline placement across
        // numberOfLines = 0 vs > 0. Drift here would defeat the whole fix.
        let longText = String(repeating: "This is a long text. ", count: 20)
        let lockedHeight: CGFloat = 24  // larger than 16pt Helvetica's natural lineHeight
        let attr = makeAttrString(
            longText,
            fontSize: 16,
            lockedLineHeight: lockedHeight
        )

        let threeLinesHeight = TextMeasurer.measure(
            attr, maxWidth: 200, maxHeight: .greatestFiniteMagnitude, maxLines: 3
        ).height

        // Three lines × locked 24pt each, no inter-line spacing = exactly 72.
        XCTAssertEqual(threeLinesHeight, lockedHeight * 3, accuracy: 1)
    }

    // MARK: - Feed Cell Layout

    func testFeedCellLayout() {
        let nameAttr = makeAttrString("John Doe", fontSize: 16)
        let bodyAttr = makeAttrString(
            "This is a post body that might span multiple lines in a real app.",
            fontSize: 14
        )
        let timeAttr = makeAttrString("2m", fontSize: 12)

        let layout = LoomLayout(width: 375) {
            VStack(spacing: 8) {
                HStack(spacing: 8, align: .center) {
                    Fixed(width: 40, height: 40).key(TestKey.avatar)
                    Text(nameAttr).key(TestKey.name).flex(grow: 1, shrink: 1)
                    Text(timeAttr).key(TestKey.time)
                }.padding(.horizontal, 12)
                Text(bodyAttr).key(TestKey.body)
                    .padding(.horizontal, 12)
            }
        }

        let result = layout.calculate()

        XCTAssertNotNil(result.frame(for: TestKey.avatar))
        XCTAssertNotNil(result.frame(for: TestKey.name))
        XCTAssertNotNil(result.frame(for: TestKey.time))
        XCTAssertNotNil(result.frame(for: TestKey.body))

        let avatar = result.frame(for: TestKey.avatar)!
        XCTAssertEqual(avatar.width, 40)
        XCTAssertEqual(avatar.height, 40)

        XCTAssertGreaterThan(result.height, 50)
        XCTAssertEqual(result.height, layout.calculateHeight())
    }

    // MARK: - String Key

    func testStringKey() {
        let layout = LoomLayout(width: 375) {
            Fixed(width: 100, height: 50).key("myView")
        }
        let result = layout.calculate()
        XCTAssertNotNil(result.frame(for: "myView"))
    }

    // MARK: - Determinism & Thread Safety

    func testMeasureIsDeterministic() {
        let attr = makeAttrString("Determinism check", fontSize: 16)

        let size1 = TextMeasurer.measure(attr, maxWidth: 200, maxHeight: .greatestFiniteMagnitude)
        let size2 = TextMeasurer.measure(attr, maxWidth: 200, maxHeight: .greatestFiniteMagnitude)

        XCTAssertEqual(size1.width, size2.width)
        XCTAssertEqual(size1.height, size2.height)
    }

    func testMeasureIsThreadSafeUnderConcurrentSameText() {
        // Many threads measuring the same attributed string concurrently must
        // not crash. (TextMeasurer creates a fresh TextKit stack per call,
        // but the global init lock around NSTextStorage / NSLayoutManager
        // construction is the safety guarantee being exercised here.)
        let attr = makeAttrString("Concurrent measurement test string that is long enough", fontSize: 14)
        let expectation = XCTestExpectation(description: "Concurrent measurements complete")
        expectation.expectedFulfillmentCount = 10

        for _ in 0..<10 {
            DispatchQueue.global().async {
                for _ in 0..<50 {
                    _ = TextMeasurer.measure(attr, maxWidth: 200, maxHeight: .greatestFiniteMagnitude)
                }
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10)
    }

    func testMeasureIsThreadSafeWithDistinctStrings() {
        // Same as above, but each thread uses a distinct attributed string.
        let expectation = XCTestExpectation(description: "Different string measurements")
        expectation.expectedFulfillmentCount = 10

        for i in 0..<10 {
            let attr = makeAttrString("String variant \(i) with some text", fontSize: 14)
            DispatchQueue.global().async {
                for _ in 0..<50 {
                    _ = TextMeasurer.measure(attr, maxWidth: 300, maxHeight: .greatestFiniteMagnitude)
                }
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10)
    }

    // MARK: - Cache

    func testLayoutCache() {
        let cache = LayoutCache()
        let layout = LoomLayout(width: 375) {
            Fixed(width: 100, height: 50).key("box")
        }

        let result = cache.resolve(id: "test-1", width: 375) {
            layout
        }
        XCTAssertEqual(result.height, 50)

        let cached = cache.get(id: "test-1", width: 375)
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached!.height, 50)

        let miss = cache.get(id: "test-1", width: 320)
        XCTAssertNil(miss)
    }

    // MARK: - RTL

    func testHStackChildrenFlipUnderRTL() {
        let buildLayout: (LoomDirection) -> LayoutResult = { dir in
            LoomLayout(width: 200, direction: dir) {
                HStack(spacing: 8) {
                    Fixed(width: 40, height: 40).key(TestKey.avatar)
                    Fixed(width: 40, height: 40).key(TestKey.name)
                }
            }.calculate()
        }

        let ltr = buildLayout(.ltr)
        let rtl = buildLayout(.rtl)

        let avatarLTR = ltr.frame(for: TestKey.avatar)!
        let nameLTR = ltr.frame(for: TestKey.name)!
        XCTAssertLessThan(avatarLTR.origin.x, nameLTR.origin.x,
                          "LTR HStack: first child should sit to the left of second")

        let avatarRTL = rtl.frame(for: TestKey.avatar)!
        let nameRTL = rtl.frame(for: TestKey.name)!
        XCTAssertGreaterThan(avatarRTL.origin.x, nameRTL.origin.x,
                             "RTL HStack: first child should sit to the right of second (mirrored)")

        // y / size unchanged across modes
        XCTAssertEqual(avatarLTR.origin.y, avatarRTL.origin.y)
        XCTAssertEqual(avatarLTR.size, avatarRTL.size)
    }

    func testPaddingLeadingResolvesToLeftUnderLTR() {
        let layout = LoomLayout(width: 200, direction: .ltr) {
            VStack {
                Fixed(width: 40, height: 40).key(TestKey.avatar)
            }.padding(.leading, 16)
        }.calculate()
        let frame = layout.frame(for: TestKey.avatar)!
        XCTAssertEqual(frame.origin.x, 16, accuracy: 0.5)
    }

    func testPaddingLeadingResolvesToRightUnderRTL() {
        let layout = LoomLayout(width: 200, direction: .rtl) {
            VStack {
                Fixed(width: 40, height: 40).key(TestKey.avatar)
            }.padding(.leading, 16)
        }.calculate()
        let frame = layout.frame(for: TestKey.avatar)!
        // Container width 200 - child 40 - leading 16 = 144
        XCTAssertEqual(frame.origin.x, 144, accuracy: 0.5)
    }

    func testPaddingLeftIsAbsoluteUnderRTL() {
        // .left is absolute — its 16pt slice always lives on the
        // physical-left side. A Spacer inside a VStack (default
        // cross-axis stretch) fills the parent's inner width, so its
        // x and width directly reveal where padding.left applied.
        let buildFrame: (LoomDirection) -> CGRect = { dir in
            let result = LoomLayout(width: 200, direction: dir) {
                VStack {
                    Spacer(40).key(TestKey.avatar)
                }.padding(.left, 16)
            }.calculate()
            return result.frame(for: TestKey.avatar)!
        }
        let ltr = buildFrame(.ltr)
        let rtl = buildFrame(.rtl)
        // Content area = [16, 200] in both directions (padding.left
        // is physical). Spacer fills it: x=16, width=184.
        XCTAssertEqual(ltr.origin.x, 16, accuracy: 0.5)
        XCTAssertEqual(rtl.origin.x, 16, accuracy: 0.5,
                       ".left padding should remain on physical left under RTL")
        XCTAssertEqual(ltr.size.width, 184, accuracy: 0.5)
        XCTAssertEqual(rtl.size.width, 184, accuracy: 0.5)
    }

    func testMarginTrailingFlipsBetweenLTRAndRTL() {
        // HStack with 8pt gap. Second child gets .margin(.trailing, 12).
        // Under LTR, trailing == right of second child, so it doesn't
        // affect inter-sibling distance. Instead test that the second
        // child's right edge moves between modes by reading its frame
        // relative to the container.
        let build: (LoomDirection) -> CGRect = { dir in
            let result = LoomLayout(width: 200, direction: dir) {
                HStack {
                    Fixed(width: 40, height: 40).key(TestKey.avatar)
                    Fixed(width: 40, height: 40)
                        .key(TestKey.name)
                        .margin(.trailing, 12)
                }
            }.calculate()
            return result.frame(for: TestKey.name)!
        }
        let ltr = build(.ltr)
        let rtl = build(.rtl)
        // In both modes, .name comes after .avatar in source order.
        // LTR: avatar.x=0, name.x=40. trailing margin pushes nothing
        // visible to the right.
        // RTL: HStack flips → avatar.x = 200-40 = 160, name.x = 120.
        XCTAssertEqual(ltr.origin.x, 40, accuracy: 0.5)
        XCTAssertEqual(rtl.origin.x, 120, accuracy: 0.5)
    }

    func testNestedDirectionOverride() {
        // LTR root containing a subtree pinned to RTL.
        let layout = LoomLayout(width: 200, direction: .ltr) {
            VStack {
                HStack(spacing: 8) {
                    Fixed(width: 40, height: 40).key(TestKey.avatar)
                    Fixed(width: 40, height: 40).key(TestKey.name)
                }.direction(.rtl)
            }
        }.calculate()
        let avatar = layout.frame(for: TestKey.avatar)!
        let name = layout.frame(for: TestKey.name)!
        // Inside the RTL subtree, avatar > name on the x axis.
        XCTAssertGreaterThan(avatar.origin.x, name.origin.x,
                             "Nested .direction(.rtl) should mirror children")
    }

    func testInheritDefaultsToSystem() {
        // .inherit at the root is the default; calculate must succeed
        // without error and produce a non-empty result. We don't assert
        // which direction is picked because that's environment-dependent.
        let layout = LoomLayout(width: 200) {
            HStack {
                Fixed(width: 40, height: 40).key(TestKey.avatar)
                Fixed(width: 40, height: 40).key(TestKey.name)
            }
        }.calculate()
        XCTAssertNotNil(layout.frame(for: TestKey.avatar))
        XCTAssertNotNil(layout.frame(for: TestKey.name))
    }

    func testAbsolutePositionLeading() {
        // LoomLayout's `width` is the absolute container's coordinate
        // space, so use width=100 to keep the math simple. ZStack sized
        // by first 100×100 child.
        let buildX: (LoomDirection) -> CGFloat = { dir in
            let result = LoomLayout(width: 100, direction: dir) {
                ZStack {
                    Fixed(width: 100, height: 100).key(TestKey.avatar)
                    Fixed(width: 16, height: 16)
                        .position(type: .absolute, top: 0, leading: 8)
                        .key(TestKey.name)
                }
            }.calculate()
            return result.frame(for: TestKey.name)!.origin.x
        }
        // LTR: leading == left → x = 8.
        // RTL: leading == right → x = 100 - 16 - 8 = 76.
        XCTAssertEqual(buildX(.ltr), 8, accuracy: 0.5)
        XCTAssertEqual(buildX(.rtl), 100 - 16 - 8, accuracy: 0.5)
    }

    func testZAlignmentTopTrailing() {
        let buildX: (LoomDirection) -> CGFloat = { dir in
            let result = LoomLayout(width: 100, direction: dir) {
                ZStack(alignment: .topTrailing) {
                    Fixed(width: 100, height: 100).key(TestKey.avatar)
                    Fixed(width: 16, height: 16).key(TestKey.name)
                }
            }.calculate()
            return result.frame(for: TestKey.name)!.origin.x
        }
        // LTR: topTrailing == top-right → x = 100 - 16 = 84.
        // RTL: topTrailing == top-left → x = 0.
        XCTAssertEqual(buildX(.ltr), 84, accuracy: 0.5)
        XCTAssertEqual(buildX(.rtl), 0, accuracy: 0.5)
    }

    // MARK: - Pluggable TextMeasuring (issue-02)

    /// Stub measurer that returns a known fixed size and counts how many
    /// times it was called — proves Loom uses the provided measurer rather
    /// than the default Core Text one.
    private final class StubMeasurer: TextMeasuring, @unchecked Sendable {
        let fixedSize = CGSize(width: 99, height: 77)
        private(set) var callCount = 0
        private let lock = NSLock()
        func measure(_ s: NSAttributedString, maxWidth: CGFloat, maxHeight: CGFloat, maxLines: Int) -> CGSize {
            lock.lock(); defer { lock.unlock() }
            callCount += 1
            return fixedSize
        }
    }

    func testCustomTextMeasurerIsInvoked() {
        let stub = StubMeasurer()
        let attr = makeAttrString("ignored", fontSize: 16)
        let result = LoomLayout(width: 200) {
            Text(attr, maxLines: 2, measurer: stub).key(TestKey.body)
        }.calculate()

        let frame = result.frame(for: TestKey.body)!
        XCTAssertEqual(frame.height, stub.fixedSize.height,
                       "Loom must use the supplied measurer's height")
        XCTAssertGreaterThan(stub.callCount, 0, "Stub measurer should have been called")
    }

    func testDefaultMeasurerSharedMatchesStaticAPI() {
        // TextMeasurer.shared is a TextMeasuring conformer that wraps the
        // existing static API. Both must return the same value for any
        // input — protects against accidental divergence if the static
        // method's signature is modified later.
        let attr = makeAttrString(String(repeating: "Hello world. ", count: 10), fontSize: 16, lineSpacing: 4)
        let viaStatic = TextMeasurer.measure(attr, maxWidth: 200, maxHeight: .greatestFiniteMagnitude, maxLines: 3)
        let viaShared = TextMeasurer.shared.measure(attr, maxWidth: 200, maxHeight: .greatestFiniteMagnitude, maxLines: 3)
        XCTAssertEqual(viaStatic, viaShared)
    }

    func testTextWithoutExplicitMeasurerUsesDefault() {
        // Backwards-compatible call site (no measurer:) must produce the
        // same result as one that explicitly passes TextMeasurer.shared.
        let attr = makeAttrString(String(repeating: "Hello world. ", count: 10), fontSize: 16, lineSpacing: 4)

        let implicit = LoomLayout(width: 200) {
            Text(attr, maxLines: 2).key(TestKey.body)
        }.calculate().frame(for: TestKey.body)!.size

        let explicit = LoomLayout(width: 200) {
            Text(attr, maxLines: 2, measurer: TextMeasurer.shared).key(TestKey.body)
        }.calculate().frame(for: TestKey.body)!.size

        XCTAssertEqual(implicit, explicit)
    }

    // MARK: - Explicit-zero position offsets

    func testPositionExplicitZeroPinsToEdge() {
        // An explicit 0 offset must pin the edge — it is NOT the same as
        // "unset". Regression test: 0 used to be treated as a sentinel
        // and silently skipped, so the badge fell back to the container's
        // justify/align placement (only coincidentally correct under the
        // default .start).
        let result = LoomLayout(width: 200, direction: .ltr) {
            VStack(justify: .center, align: .center) {
                Fixed(width: 100, height: 100).key(TestKey.avatar)
                Fixed(width: 20, height: 20)
                    .position(type: .absolute, top: 0, right: 0)
                    .key(TestKey.name)
            }.size(height: 300)
        }.calculate()

        let badge = result.frame(for: TestKey.name)!
        XCTAssertEqual(badge.origin.y, 0, accuracy: 0.5,
                       "top: 0 must pin to the top edge, not center")
        XCTAssertEqual(badge.origin.x, 200 - 20, accuracy: 0.5,
                       "right: 0 must pin to the right edge, not center")
    }

    // MARK: - Root-level padded leaf

    func testRootLeafWithPaddingKeyReturnsContentFrame() {
        // A padded leaf at the ROOT of the layout must report its content
        // area (same semantics as when nested), not the padded wrapper.
        let result = LoomLayout(width: 200) {
            Fixed(width: 50, height: 40).padding(10).key(TestKey.avatar)
        }.calculate()

        let frame = result.frame(for: TestKey.avatar)!
        XCTAssertEqual(frame, CGRect(x: 10, y: 10, width: 50, height: 40))
        XCTAssertEqual(result.height, 60, accuracy: 0.5)
    }

    // MARK: - LayoutCache id semantics

    private func makeResult(height: CGFloat) -> LayoutResult {
        LoomLayout(width: 100) { Fixed(width: 100, height: height) }.calculate()
    }

    func testInvalidateIsScopedToExactId() {
        // Regression: string-prefix invalidation used to wipe entries for
        // any id whose description started with "<id>-".
        let cache = LayoutCache()
        cache.set(id: "item-1", width: 320, result: makeResult(height: 10))
        cache.set(id: "item-1-detail", width: 320, result: makeResult(height: 20))

        cache.invalidate(id: "item-1")

        XCTAssertNil(cache.get(id: "item-1", width: 320))
        XCTAssertEqual(cache.get(id: "item-1-detail", width: 320)?.height, 20,
                       "invalidating \"item-1\" must not touch \"item-1-detail\"")
    }

    func testDistinctIdTypesDoNotCollide() {
        // Regression: keys were "\(id)-\(width)" strings, so Int 1 and
        // String "1" collided.
        let cache = LayoutCache()
        cache.set(id: 1, width: 320, result: makeResult(height: 10))
        cache.set(id: "1", width: 320, result: makeResult(height: 20))

        XCTAssertEqual(cache.get(id: 1, width: 320)?.height, 10)
        XCTAssertEqual(cache.get(id: "1", width: 320)?.height, 20)
    }

    func testLRUEvictsLeastRecentlyUsed() {
        let cache = LayoutCache(countLimit: 2)
        cache.set(id: "a", width: 320, result: makeResult(height: 1))
        cache.set(id: "b", width: 320, result: makeResult(height: 2))
        _ = cache.get(id: "a", width: 320)  // touch "a" so "b" is oldest
        cache.set(id: "c", width: 320, result: makeResult(height: 3))

        XCTAssertNotNil(cache.get(id: "a", width: 320))
        XCTAssertNil(cache.get(id: "b", width: 320), "least recently used entry must be evicted")
        XCTAssertNotNil(cache.get(id: "c", width: 320))
    }

    // MARK: - TextKitMeasurer

    func testTextKitMeasurerBasics() {
        let attr = makeAttrString(String(repeating: "Hello world. ", count: 12), fontSize: 15)

        let size = TextKitMeasurer.shared.measure(
            attr, maxWidth: 220, maxHeight: .greatestFiniteMagnitude, maxLines: 0
        )
        XCTAssertGreaterThan(size.height, 0)
        XCTAssertLessThanOrEqual(size.width, 220)

        // Deterministic
        let again = TextKitMeasurer.shared.measure(
            attr, maxWidth: 220, maxHeight: .greatestFiniteMagnitude, maxLines: 0
        )
        XCTAssertEqual(size, again)

        // maxLines caps below the unbounded height
        let capped = TextKitMeasurer.shared.measure(
            attr, maxWidth: 220, maxHeight: .greatestFiniteMagnitude, maxLines: 2
        )
        XCTAssertLessThan(capped.height, size.height)

        // Thread-safe under concurrent use (fresh stack per call)
        let exp = expectation(description: "concurrent TextKit measurement")
        exp.expectedFulfillmentCount = 8
        for _ in 0..<8 {
            DispatchQueue.global().async {
                let s = TextKitMeasurer.shared.measure(
                    attr, maxWidth: 220, maxHeight: .greatestFiniteMagnitude, maxLines: 0
                )
                XCTAssertEqual(s, size)
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 5)
    }

    func testDefaultTextMeasurerIsUsedByTextFactory() {
        // Text() without an explicit measurer must pick up the global
        // default at build time.
        let stub = StubMeasurer()
        let saved = Loom.defaultTextMeasurer
        Loom.defaultTextMeasurer = stub
        defer { Loom.defaultTextMeasurer = saved }

        let attr = makeAttrString("ignored", fontSize: 16)
        let result = LoomLayout(width: 200) {
            Text(attr).key(TestKey.body)
        }.calculate()

        XCTAssertEqual(result.frame(for: TestKey.body)!.height, stub.fixedSize.height)
        XCTAssertGreaterThan(stub.callCount, 0)
    }

    #if canImport(UIKit)
    func testLockLineHeightPicksTallestFont() {
        let small = UIFont.systemFont(ofSize: 12)
        let big = UIFont.boldSystemFont(ofSize: 24)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.lockLineHeight(toTallestOf: [small, big])

        XCTAssertEqual(style.minimumLineHeight, big.lineHeight)
        XCTAssertEqual(style.maximumLineHeight, big.lineHeight)
        XCTAssertEqual(style.lineSpacing, 4, "must compose with existing spacing")

        // Empty input leaves the style untouched instead of locking to 0.
        let untouched = NSMutableParagraphStyle()
        untouched.lockLineHeight(toTallestOf: [])
        XCTAssertEqual(untouched.minimumLineHeight, 0)
        XCTAssertEqual(untouched.maximumLineHeight, 0)
    }

    /// TextKitMeasurer's whole contract: agree with UILabel for arbitrary
    /// attributed strings WITHOUT any locked-line-height discipline.
    func testTextKitMeasurerMatchesUILabel() {
        let plain = NSAttributedString(
            string: String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 6),
            attributes: [.font: UIFont.systemFont(ofSize: 14)]
        )

        let mixed: NSAttributedString = {
            let m = NSMutableAttributedString(
                string: "Mixed sizes: big bold headline inside small body text, "
                    + "plus `mono code` runs — no paragraph style anywhere. "
                    + "This is exactly the case Core Text disagrees with UILabel on.",
                attributes: [.font: UIFont.systemFont(ofSize: 13)]
            )
            m.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: 19), range: NSRange(location: 13, length: 17))
            m.addAttribute(.font, value: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular), range: NSRange(location: 61, length: 11))
            return m
        }()

        let spaced: NSAttributedString = {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 6
            return NSAttributedString(
                string: String(repeating: "Line spacing without locked line heights. ", count: 5),
                attributes: [.font: UIFont.systemFont(ofSize: 15), .paragraphStyle: style]
            )
        }()

        let width: CGFloat = 300
        for (name, attr) in [("plain", plain), ("mixedFonts", mixed), ("lineSpacing", spaced)] {
            for maxLines in [0, 2, 3] {
                let measured = TextKitMeasurer.shared.measure(
                    attr, maxWidth: width, maxHeight: .greatestFiniteMagnitude, maxLines: maxLines
                )

                let label = UILabel()
                label.attributedText = attr
                label.numberOfLines = maxLines
                let labelSize = label.sizeThatFits(
                    CGSize(width: width, height: .greatestFiniteMagnitude)
                )

                XCTAssertEqual(
                    measured.height, labelSize.height, accuracy: 1.0,
                    "TextKitMeasurer disagrees with UILabel for \(name) at maxLines=\(maxLines)"
                )
            }
        }
    }
    #endif

    // MARK: - measureDetails

    private var detailMeasurers: [(name: String, measurer: any TextMeasuring)] {
        [("CoreText", TextMeasurer.shared), ("TextKit", TextKitMeasurer.shared)]
    }

    func testMeasureDetailsSemantics() {
        let attr = makeAttrString(String(repeating: "Hello wrapping world. ", count: 10), fontSize: 15)

        for (name, measurer) in detailMeasurers {
            // Capped at 2 lines: truncated, partial range.
            let capped = measurer.measureDetails(
                attr, maxWidth: 200, maxHeight: .greatestFiniteMagnitude, maxLines: 2
            )
            guard let details = capped.details else {
                return XCTFail("\(name): built-in measurer must provide details")
            }
            XCTAssertEqual(details.lineCount, 2, name)
            XCTAssertTrue(details.isTruncated, name)
            XCTAssertEqual(details.visibleRange.location, 0, name)
            XCTAssertLessThan(details.visibleRange.length, attr.length, name)
            XCTAssertGreaterThan(details.visibleRange.length, 0, name)
            XCTAssertGreaterThan(details.lastLineWidth, 0, name)
            XCTAssertLessThanOrEqual(details.lastLineWidth, capped.size.width + 0.5, name)
            XCTAssertGreaterThan(details.firstBaseline, 0, name)
            XCTAssertGreaterThan(details.lastBaseline, details.firstBaseline, name)
            XCTAssertLessThanOrEqual(details.lastBaseline, capped.size.height, name)

            // Unbounded: everything visible, nothing truncated.
            let full = measurer.measureDetails(
                attr, maxWidth: 200, maxHeight: .greatestFiniteMagnitude, maxLines: 0
            )
            guard let fullDetails = full.details else {
                return XCTFail("\(name): built-in measurer must provide details")
            }
            XCTAssertFalse(fullDetails.isTruncated, name)
            XCTAssertEqual(fullDetails.visibleRange, NSRange(location: 0, length: attr.length), name)
            XCTAssertGreaterThan(fullDetails.lineCount, 2, name)
        }
    }

    func testMeasureDetailsSizeMatchesMeasure() {
        // The contract on the protocol: details.size == measure() for the
        // same inputs — always, including the truncated case.
        let attr = makeAttrString(
            String(repeating: "Size parity across paths. ", count: 8),
            fontSize: 14, lineSpacing: 3
        )
        for (name, measurer) in detailMeasurers {
            for maxLines in [0, 1, 2, 5] {
                let plain = measurer.measure(
                    attr, maxWidth: 240, maxHeight: .greatestFiniteMagnitude, maxLines: maxLines
                )
                let detailed = measurer.measureDetails(
                    attr, maxWidth: 240, maxHeight: .greatestFiniteMagnitude, maxLines: maxLines
                )
                XCTAssertEqual(detailed.size, plain, "\(name) maxLines=\(maxLines)")
            }
        }
    }

    func testMeasureDetailsCrossEngineAgreement() {
        // Line breaking is CoreText-based in both engines — the
        // engine-agnostic fields must agree on plain text. Absolute
        // baselines are renderer-specific by design (CT includes font
        // leading, TextKit mirrors UILabel and ignores it), so those are
        // NOT compared here — see the invariant test below.
        let attr = makeAttrString(
            String(repeating: "Agreement between engines matters here. ", count: 6),
            fontSize: 15
        )
        let ct = TextMeasurer.shared.measureDetails(
            attr, maxWidth: 260, maxHeight: .greatestFiniteMagnitude, maxLines: 3
        ).details!
        let tk = TextKitMeasurer.shared.measureDetails(
            attr, maxWidth: 260, maxHeight: .greatestFiniteMagnitude, maxLines: 3
        ).details!

        XCTAssertEqual(ct.lineCount, tk.lineCount)
        XCTAssertEqual(ct.isTruncated, tk.isTruncated)
        XCTAssertEqual(ct.visibleRange, tk.visibleRange,
                       "natural line breaks must match across engines")
        XCTAssertEqual(ct.lastLineWidth, tk.lastLineWidth, accuracy: 1.5,
                       "trailing whitespace must be excluded by both engines")
    }

    func testMeasureDetailsBaselineSpacingAgreesUnderLockedLineHeight() {
        // Locking the line height pins both engines to the same line
        // grid, so baseline SPACING must agree exactly — the invariant
        // that makes locked-line-height strings render identically.
        let locked: CGFloat = 22
        let attr = makeAttrString(
            String(repeating: "Locked grid baseline spacing. ", count: 6),
            fontSize: 15, lockedLineHeight: locked
        )
        for (name, measurer) in detailMeasurers {
            let details = measurer.measureDetails(
                attr, maxWidth: 240, maxHeight: .greatestFiniteMagnitude, maxLines: 3
            ).details!
            XCTAssertEqual(details.lineCount, 3, name)
            let spacing = (details.lastBaseline - details.firstBaseline)
                / CGFloat(details.lineCount - 1)
            XCTAssertEqual(spacing, locked, accuracy: 0.5,
                           "\(name): baseline spacing must equal the locked line height")
        }
    }

    func testMeasureDetailsDefaultImplementationReturnsNilDetails() {
        // A conformer that only implements measure() gets the protocol's
        // default: correct size, nil details.
        let stub = StubMeasurer()
        let attr = makeAttrString("anything", fontSize: 16)
        let m = stub.measureDetails(
            attr, maxWidth: 100, maxHeight: 100, maxLines: 0
        )
        XCTAssertEqual(m.size, stub.fixedSize)
        XCTAssertNil(m.details)
    }

    func testMeasureDetailsEmptyString() {
        for (name, measurer) in detailMeasurers {
            let m = measurer.measureDetails(
                NSAttributedString(string: ""),
                maxWidth: 100, maxHeight: 100, maxLines: 2
            )
            XCTAssertEqual(m.size, .zero, name)
            XCTAssertEqual(m.details, .empty, name)
        }
    }

    func testSystemDirectionDoesNotCrashOffMain() {
        // Verify Loom.systemDirection is callable concurrently from
        // background threads without crashing. The exact value depends
        // on the test environment's locale.
        let exp = expectation(description: "off-main reads of systemDirection")
        exp.expectedFulfillmentCount = 10
        for _ in 0..<10 {
            DispatchQueue.global().async {
                for _ in 0..<50 {
                    let dir = Loom.systemDirection
                    XCTAssertTrue(dir == .ltr || dir == .rtl)
                }
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 5)
    }
}
