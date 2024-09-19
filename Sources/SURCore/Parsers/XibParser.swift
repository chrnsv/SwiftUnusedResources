import Foundation
import IBDecodable
import PathKit

class XibParser {
    func parse(
        _ path: Path
    ) throws -> [ExploreUsage] {
        let resources: [AnyResource]?
        
        if path.extension == "xib" {
            let file = try XibFile(url: path.url)
            resources = file.document.resources
        }
        else if path.extension == "storyboard" {
            let file = try StoryboardFile(url: path.url)
            resources = file.document.resources
        }
        else {
            throw XibParserError.wrongExtension
        }
        
        guard let resources else {
            return []
        }
        
        return resources
            .compactMap { $0.resource.toExploreUsage() }
    }
}

private extension XibParser {
    enum XibParserError: Error {
        case wrongExtension
    }
}

private extension ResourceProtocol {
    func toExploreUsage() -> ExploreUsage? {
        if let image = self as? Image {
            return .string(image.name, .image)
        }
        else if let color = self as? NamedColor {
            return .string(color.name, .color)
        }
        
        return nil
    }
}
