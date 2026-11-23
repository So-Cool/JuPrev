import NotebookKit
import SwiftUI

/// The outline sidebar's state, shared with the notebook view.
final class OutlineModel: ObservableObject {
    @Published var headings: [NotebookHeading] = []
    /// The heading of the section being read; set by the viewer as you scroll.
    @Published var current: String?
    /// Called when the user picks a heading.
    var onSelect: ((String) -> Void)?
}

struct OutlineView: View {
    @ObservedObject var model: OutlineModel

    var body: some View {
        if model.headings.isEmpty {
            Text("No headings")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let topLevel = model.headings.map(\.level).min() ?? 1
            ScrollViewReader { proxy in
                List(selection: selection) {
                    ForEach(model.headings, id: \.id) { heading in
                        Text(heading.text)
                            .lineLimit(2)
                            .fontWeight(heading.level == topLevel ? .semibold : .regular)
                            .padding(.leading, CGFloat(heading.level - topLevel) * 12)
                            .tag(heading.id)
                            .id(heading.id)
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: model.current) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
    }

    /// Picking a row scrolls the notebook; the viewer's own updates (as you scroll)
    /// only move the highlight.
    private var selection: Binding<String?> {
        Binding(
            get: { model.current },
            set: { id in
                guard let id else { return }
                model.current = id
                model.onSelect?(id)
            }
        )
    }
}
