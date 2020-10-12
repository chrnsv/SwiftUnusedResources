import Foundation
import IBDecodable
import PathKit

enum XibParserError: Error {
    case wrongExtension
}

class XibParser {
    @discardableResult
    init(_ path: Path, _ register: @escaping ImageRegister) throws {
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

        resources?.forEach { resource in
            guard let image = resource.resource as? Image else {
                return
            }

            register(.string(image.name))
        }
    }
}
