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
    @State private var themes = Themes.available()
    @State private var saveError: String?

    var body: some View {
        Form {
            Section("Notebook") {
                Picker("Theme", selection: $settings.theme) {
                    ForEach(themes, id: \.id) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                LabeledContent {
                    Button("Open Themes Folder") { ThemeMenu.openThemesFolder() }
                } label: {
                    Text("Custom themes")
                    Text("CSS files in this folder appear as themes. After editing one, View ▸ Reload (⌘R) applies it.")
                }
                Toggle("Show code", isOn: $settings.showCode)
                Toggle("Show outputs", isOn: $settings.showOutputs)
                Toggle(isOn: $settings.showStderr) {
                    Text("Show stderr")
                    Text("Warnings, progress bars and logs written to standard error. Errors and tracebacks are always shown.")
                }
                Text("Defaults for Quick Look and for windows. View ▸ Show Code, Show Outputs and Show stderr change just the current window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
        // The View ▸ Theme menu changes settings too; pick that up.
        .onReceive(NotificationCenter.default.publisher(for: .juprevSettingsDidChange)) { _ in
            let saved = JuPrevSettings.load()
            if saved != settings { settings = saved }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            themes = Themes.available()
        }
        .onChange(of: settings) { _, newValue in
            guard newValue != JuPrevSettings.load() else { return }
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
