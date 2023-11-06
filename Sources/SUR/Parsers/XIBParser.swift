import Foundation
import IBDecodable
import PathKit

enum XibParserError: Error {
    case wrongExtension
}

class XibParser {
    func parse(
        _ path: Path
    ) throws -> [ExploreUsage] {
        let resources: [AnyResource]?
        
        if (path.extension == "xib") {
            let file = try XibFile(url: path.url)
            resources = file.document.resources
        }
        else if (path.extension == "storyboard") {
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
            .compactMap { $0.resource as? Image }
            .map {.string($0.name) }
    }
}
