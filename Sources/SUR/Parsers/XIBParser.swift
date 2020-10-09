import Foundation
import IBDecodable
import PathKit

enum XibParserError: Error {
    case wrongExtension
}

class XibParser {
    @discardableResult
    init(_ path: Path, _ register: @escaping ImageRegister) throws {
        let content: IBElement
        
        if (path.extension == "xib") {
            let file = try XibFile(url: path.url)
            content = file.document
        }
        else if (path.extension == "storyboard") {
//            print("LOAD story")
            
            let file = try StoryboardFile(url: path.url)
            content = file.document
        }
        else {
            throw XibParserError.wrongExtension
        }
        
        let images = content.children(of: ImageView.self)
        images.forEach { image in
            if let image = image.image {
                register(.string(image))
            }
        }
        
        let buttons = content.children(of: Button.self)
        buttons.forEach { button in
            button.state?.forEach { state in
                if let image = state.image {
                    register(.string(image))
                }
            }
        }
    }
}
