import Foundation
import PathKit

package struct XibParser: Sendable {
    package init() {}

    package func parse(
        _ path: Path
    ) throws -> [ExploreUsage] {
        guard path.extension == "xib" || path.extension == "storyboard" else {
            throw XibParserError.wrongExtension
        }
        
        guard let parser = XMLParser(contentsOf: path.url) else {
            throw XibParserError.unreadable
        }
        
        let collector = ResourcesCollector()
        parser.delegate = collector
        
        guard parser.parse() else {
            throw parser.parserError ?? XibParserError.malformed
        }
        
        return collector.usages
    }
}

private extension XibParser {
    enum XibParserError: Error {
        case wrongExtension
        case unreadable
        case malformed
    }
}

/// Collects images and named colors declared in the `<resources>` section of the document.
private final class ResourcesCollector: NSObject, XMLParserDelegate {
    private(set) var usages: [ExploreUsage] = []
    private var elements: [String] = []
    
    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elements == ["document", "resources"], let name = attributeDict["name"] {
            switch elementName {
            case "image": usages.append(.string(name, .image))
            case "namedColor": usages.append(.string(name, .color))
            default: break
            }
        }
        
        elements.append(elementName)
    }
    
    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        elements.removeLast()
    }
}
