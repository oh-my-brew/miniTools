import Foundation
import UniformTypeIdentifiers

struct DefaultApplicationFileType: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let filenameExtensions: [String]
    let expectedContentTypeIdentifier: String

    var extensionSummary: String {
        filenameExtensions.map { ".\($0)" }.joined(separator: "、")
    }

    var resolvedContentType: UTType? {
        guard filenameExtensions.allSatisfy({ filenameExtension in
            Self.contentTypes(for: filenameExtension).contains(where: {
                $0.identifier == expectedContentTypeIdentifier
            })
        }) else {
            return nil
        }
        return UTType(expectedContentTypeIdentifier)
    }

    static func contentTypes(for filenameExtension: String) -> [UTType] {
        UTType.types(
            tag: filenameExtension,
            tagClass: .filenameExtension,
            conformingTo: nil
        )
    }
}

enum DefaultApplicationFileTypeCatalog {
    static let supported: [DefaultApplicationFileType] = [
        fileType("plain-text", "纯文本", ["txt"], "public.plain-text"),
        fileType("markdown", "Markdown", ["md", "markdown"], "net.daringfireball.markdown"),
        fileType("json", "JSON", ["json"], "public.json"),
        fileType("yaml", "YAML", ["yaml", "yml"], "public.yaml"),
        fileType("xml", "XML", ["xml"], "public.xml"),
        fileType("html", "HTML", ["html", "htm"], "public.html"),
        fileType("css", "CSS", ["css"], "public.css"),
        fileType("javascript", "JavaScript", ["js"], "com.netscape.javascript-source"),
        fileType("shell", "Shell 脚本", ["sh"], "public.shell-script"),
        fileType("python", "Python", ["py"], "public.python-script"),
        fileType("ruby", "Ruby", ["rb"], "public.ruby-script"),
        fileType("swift", "Swift", ["swift"], "public.swift-source")
    ]

    private static func fileType(
        _ id: String,
        _ title: String,
        _ filenameExtensions: [String],
        _ contentTypeIdentifier: String
    ) -> DefaultApplicationFileType {
        DefaultApplicationFileType(
            id: id,
            title: title,
            filenameExtensions: filenameExtensions,
            expectedContentTypeIdentifier: contentTypeIdentifier
        )
    }
}
