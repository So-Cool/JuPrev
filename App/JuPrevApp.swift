import SwiftUI

// Placeholder until phase 3 (the viewer). Launching the app once registers the
// Quick Look extension and the .ipynb file type with macOS.
@main
struct JuPrevApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 8) {
                Text("JuPrev").font(.title2.weight(.semibold))
                Text("Quick Look previews for Jupyter notebooks are installed.\nSelect a .ipynb file in Finder and press Space.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(40)
        }
        .windowResizability(.contentSize)
    }
}
