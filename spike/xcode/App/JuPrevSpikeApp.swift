import SwiftUI

/// The real home folder (inside the sandbox, NSHomeDirectory() points at the container).
func realHome() -> URL {
    URL(fileURLWithPath: String(cString: getpwuid(getuid())!.pointee.pw_dir), isDirectory: true)
}

@main
struct JuPrevSpikeApp: App {
    init() {
        // Spike: share settings with the extension through a plain file instead of an App Group.
        let dir = realHome().appendingPathComponent("Library/Application Support/JuPrevSpike")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let stamp = Int(Date().timeIntervalSince1970)
            try Data(#"{"trustParentFolders": true, "stamp": \#(stamp)}"#.utf8)
                .write(to: dir.appendingPathComponent("settings.json"))
            NSLog("JUPREV app: wrote settings stamp=\(stamp)")
        } catch {
            NSLog("JUPREV app: write FAILED \(error)")
        }
    }
    var body: some Scene {
        WindowGroup {
            Text("JuPrev spike — launch once to register the Quick Look extension.")
                .padding(40)
        }
    }
}
