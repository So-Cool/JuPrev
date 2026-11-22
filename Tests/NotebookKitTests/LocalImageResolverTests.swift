import Foundation
import Testing
@testable import NotebookKit

/// Builds a throwaway tree:
///
///     root/
///       nb/            <- notebook folder
///         a.png
///         sub/b.png
///         notes.txt
///         escape -> root/outside      (symlink leading out)
///         inner  -> nb/sub            (symlink staying in)
///       outside/c.png
///       nbx/d.png                      (sibling whose name extends "nb")
struct LocalImageResolverTests {
    let root: URL
    let notebookFolder: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("juprev-tests-\(UUID().uuidString)")
        notebookFolder = root.appendingPathComponent("nb")
        let fm = FileManager.default
        for dir in ["nb/sub", "outside", "nbx"] {
            try fm.createDirectory(at: root.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        for file in ["nb/a.png", "nb/sub/b.png", "outside/c.png", "nbx/d.png"] {
            try png.write(to: root.appendingPathComponent(file))
        }
        try Data("text".utf8).write(to: root.appendingPathComponent("nb/notes.txt"))
        try fm.createSymbolicLink(at: notebookFolder.appendingPathComponent("escape"), withDestinationURL: root.appendingPathComponent("outside"))
        try fm.createSymbolicLink(at: notebookFolder.appendingPathComponent("inner"), withDestinationURL: notebookFolder.appendingPathComponent("sub"))
    }

    func resolve(_ src: String, _ policy: LocalImagePolicy = .notebookFolder) -> LocalImageResolver.Resolution {
        LocalImageResolver(notebookFolder: notebookFolder, policy: policy).resolve(src)
    }

    func isLoaded(_ r: LocalImageResolver.Resolution) -> Bool {
        if case .dataURI(let uri) = r { return uri.hasPrefix("data:image/png;base64,") }
        return false
    }

    @Test func loadsFilesInNotebookFolderAndBelow() {
        #expect(isLoaded(resolve("a.png")))
        #expect(isLoaded(resolve("./a.png")))
        #expect(isLoaded(resolve("sub/b.png")))
        #expect(isLoaded(resolve("sub/../a.png")))
        #expect(isLoaded(resolve("inner/b.png")))
    }

    @Test func refusesParentTraversalByDefault() {
        #expect(resolve("../outside/c.png") == .blocked(.outsideNotebookFolder))
        #expect(resolve("sub/../../outside/c.png") == .blocked(.outsideNotebookFolder))
        #expect(resolve("../nbx/d.png") == .blocked(.outsideNotebookFolder))
    }

    @Test func refusesSymlinksLeadingOutside() {
        #expect(resolve("escape/c.png") == .blocked(.outsideNotebookFolder))
    }

    @Test func trustParentFoldersAllowsClimbing() {
        #expect(isLoaded(resolve("../outside/c.png", .trustParentFolders)))
        #expect(isLoaded(resolve("escape/c.png", .trustParentFolders)))
        #expect(isLoaded(resolve("a.png", .trustParentFolders)))
    }

    @Test(arguments: [LocalImagePolicy.notebookFolder, .trustParentFolders])
    func alwaysRefusesAbsolutePaths(policy: LocalImagePolicy) {
        let absolute = root.appendingPathComponent("outside/c.png")
        #expect(resolve(absolute.path, policy) == .blocked(.absolutePath))
        #expect(resolve(absolute.absoluteString, policy) == .blocked(.absolutePath))
        #expect(resolve("~/c.png", policy) == .blocked(.absolutePath))
    }

    @Test func disabledReadsNothing() {
        #expect(resolve("a.png", .disabled) == .blocked(.disabled))
    }

    @Test func handlesURLSyntax() throws {
        try Data([0x89]).write(to: notebookFolder.appendingPathComponent("with space.png"))
        #expect(isLoaded(resolve("with%20space.png")))
        #expect(isLoaded(resolve("a.png?raw=true")))
        #expect(isLoaded(resolve("a.png#fragment")))
        #expect(resolve("ftp:a.png") == .blocked(.unsupported))
    }

    @Test func reportsMissingAndUnsupportedFiles() {
        #expect(resolve("nope.png") == .blocked(.missing))
        #expect(resolve("sub") == .blocked(.unsupported))
        #expect(resolve("sub.png") == .blocked(.missing))
        #expect(resolve("notes.txt") == .blocked(.unsupported))
        #expect(resolve("") == .blocked(.missing))
    }

    @Test func isInsideComparesWholeComponents() {
        let folder = URL(fileURLWithPath: "/a/nb")
        #expect(LocalImageResolver.isInside(URL(fileURLWithPath: "/a/nb/x.png"), folder))
        #expect(!LocalImageResolver.isInside(URL(fileURLWithPath: "/a/nbx/x.png"), folder))
        #expect(!LocalImageResolver.isInside(URL(fileURLWithPath: "/a/nb"), folder))
    }
}
