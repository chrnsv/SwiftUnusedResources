import Foundation
import PathKit
import Testing

@testable import SURCore

@Suite("XIB / storyboard resource extraction")
struct XibParserTests {
    private let parser = XibParser()

    private let imageResource = #"<image name="header" width="100" height="100"/>"#

    private let colorResource = """
    <namedColor name="brandBackground">
        <color red="1" green="0.5" blue="0.0" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
    </namedColor>
    """

    private func xibDocument(resources: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB.XMLIB" version="3.0" \
        toolsVersion="22155" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES">
            <resources>
        \(resources)
            </resources>
        </document>
        """
    }

    private func storyboardDocument(resources: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" \
        toolsVersion="22155" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES">
            <resources>
        \(resources)
            </resources>
        </document>
        """
    }

    // MARK: - XIB files

    @Test("Extracts an image from a xib")
    func xibImage() throws {
        let tmp = try TemporaryDirectory()
        defer { tmp.remove() }

        let path = try tmp.write("Test.xib", xibDocument(resources: imageResource))
        let usages = try parser.parse(path)

        #expect(usages == [.string("header", .image)])
    }

    @Test("Extracts a named color from a xib")
    func xibNamedColor() throws {
        let tmp = try TemporaryDirectory()
        defer { tmp.remove() }

        let path = try tmp.write("Test.xib", xibDocument(resources: colorResource))
        let usages = try parser.parse(path)

        #expect(usages == [.string("brandBackground", .color)])
    }

    @Test("Extracts images and colors together")
    func xibImageAndColor() throws {
        let tmp = try TemporaryDirectory()
        defer { tmp.remove() }

        let path = try tmp.write("Test.xib", xibDocument(resources: imageResource + "\n" + colorResource))
        let usages = try parser.parse(path)

        #expect(usages.count == 2)
        #expect(usages.contains(.string("header", .image)))
        #expect(usages.contains(.string("brandBackground", .color)))
    }

    @Test("Returns nothing for a xib without resources")
    func xibWithoutResources() throws {
        let tmp = try TemporaryDirectory()
        defer { tmp.remove() }

        let path = try tmp.write("Test.xib", xibDocument(resources: ""))
        let usages = try parser.parse(path)

        #expect(usages.isEmpty)
    }

    @Test("Ignores system colors")
    func xibSystemColorIgnored() throws {
        let tmp = try TemporaryDirectory()
        defer { tmp.remove() }

        let systemColor = """
        <systemColor name="systemBackgroundColor">
            <color white="1" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>
        </systemColor>
        """

        let path = try tmp.write("Test.xib", xibDocument(resources: systemColor + "\n" + colorResource))
        let usages = try parser.parse(path)

        #expect(usages == [.string("brandBackground", .color)])
    }

    @Test("Ignores elements outside of the resources section and tolerates unknown ones")
    func xibElementsOutsideResources() throws {
        let tmp = try TemporaryDirectory()
        defer { tmp.remove() }

        let document = """
        <?xml version="1.0" encoding="UTF-8"?>
        <document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB.XMLIB" version="3.0">
            <objects>
                <someFutureView id="abc">
                    <image name="notAResource" width="1" height="1"/>
                    <namedColor name="notAResourceEither"/>
                </someFutureView>
            </objects>
            <resources>
                <image name="header" width="100" height="100"/>
                <someFutureResource name="ignored">
                    <image name="nested" width="1" height="1"/>
                </someFutureResource>
            </resources>
        </document>
        """

        let path = try tmp.write("Test.xib", document)
        let usages = try parser.parse(path)

        #expect(usages == [.string("header", .image)])
    }

    // MARK: - Storyboard files

    @Test("Extracts images and colors from a storyboard")
    func storyboardResources() throws {
        let tmp = try TemporaryDirectory()
        defer { tmp.remove() }

        let path = try tmp.write(
            "Test.storyboard",
            storyboardDocument(resources: imageResource + "\n" + colorResource)
        )
        let usages = try parser.parse(path)

        #expect(usages.count == 2)
        #expect(usages.contains(.string("header", .image)))
        #expect(usages.contains(.string("brandBackground", .color)))
    }

    // MARK: - Errors

    @Test("Throws for an unsupported file extension")
    func wrongExtension() throws {
        let tmp = try TemporaryDirectory()
        defer { tmp.remove() }

        let path = try tmp.write("Test.txt", "not an interface builder file")

        #expect(throws: (any Error).self) {
            try parser.parse(path)
        }
    }

    @Test("Throws for malformed XML")
    func malformedXML() throws {
        let tmp = try TemporaryDirectory()
        defer { tmp.remove() }

        let path = try tmp.write("Test.xib", "<document><resources>")

        #expect(throws: (any Error).self) {
            try parser.parse(path)
        }
    }
}
