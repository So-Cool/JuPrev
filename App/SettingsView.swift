import AppKit
import NotebookKit
import SwiftUI

final class SettingsViewController: NSHostingController<SettingsView> {
    init() { super.init(rootView: SettingsView()) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// Edits the settings file shared with the Quick Look extension.
struct SettingsView: View {
    @State private var settings = JuPrevSettings.load()
    @State private var saveError: String?

    var body: some View {
        Form {
            Section("Images") {
                Toggle(isOn: $settings.trustParentFolders) {
                    Text("Load images from parent folders")
                    Text("Markdown images normally load only from the notebook's folder and its subfolders. Turn this on to also allow paths like ../figures/plot.png. Applies to the app and Quick Look.")
                }
                Toggle(isOn: $settings.loadRemoteImages) {
                    Text("Load remote images")
                    Text("Images linked from the web (https://…). Loading them can tell their server that you opened the notebook. Quick Look never loads remote images.")
                }
            }
            if let saveError {
                Text(saveError).foregroundStyle(.red).font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize()
        .onChange(of: settings) { _, newValue in
            do {
                try newValue.save()
                saveError = nil
                NotificationCenter.default.post(name: .juprevSettingsDidChange, object: nil)
            } catch {
                saveError = "Couldn't save settings: \(error.localizedDescription)"
            }
        }
    }
}
