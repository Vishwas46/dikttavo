import SwiftData
import SwiftUI

struct HistoryView: View {
    /// Set in the iPad/Mac sidebar, where rows select into it instead of
    /// pushing a detail screen.
    var selection: Binding<DictationRecord?>? = nil

    @Environment(\.modelContext) private var context
    @Query(sort: \DictationRecord.createdAt, order: .reverse) private var records: [DictationRecord]
    @State private var confirmClearAll = false

    var body: some View {
        Group {
            if records.isEmpty {
                ContentUnavailableView(
                    "No dictations yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Finished dictations appear here. Everything stays on this device.")
                )
            } else {
                List(selection: selection) {
                    ForEach(records) { record in
                        row(for: record)
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    delete([record])
                                }
                            }
                    }
                    .onDelete { offsets in
                        delete(offsets.map { records[$0] })
                    }
                }
            }
        }
        .navigationTitle("History")
        .toolbar {
            if !records.isEmpty {
                Button("Clear All", role: .destructive) {
                    confirmClearAll = true
                }
            }
        }
        .confirmationDialog("Delete all dictations?", isPresented: $confirmClearAll, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) {
                delete(records)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// In the sidebar the link's value becomes the split view's selection; on
    /// iPhone it pushes the detail screen.
    private func row(for record: DictationRecord) -> some View {
        NavigationLink(value: record) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.displayText)
                    .font(.body)
                    .lineLimit(2)
                Text(record.createdAt, format: .dateTime.day().month().year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func delete(_ doomed: [DictationRecord]) {
        // Never leave the detail pane showing a deleted record.
        if let selected = selection?.wrappedValue, doomed.contains(selected) {
            selection?.wrappedValue = nil
        }
        for record in doomed {
            context.delete(record)
        }
    }
}

struct HistoryDetailView: View {
    let record: DictationRecord
    @State private var mode: DictationView.TranscriptMode = .raw
    @State private var justCopied = false

    private var shownText: String {
        mode == .cleaned ? (record.cleanedText ?? record.rawText) : record.rawText
    }

    var body: some View {
        VStack(spacing: 8) {
            if record.cleanedText != nil {
                Picker("Transcript", selection: $mode) {
                    ForEach(DictationView.TranscriptMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
            }
            ScrollView {
                Text(shownText)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .navigationTitle(Text(record.createdAt, format: .dateTime.day().month().hour().minute()))
        .inlineNavigationTitle()
        .toolbar {
            Button {
                Platform.copyToClipboard(shownText)
                justCopied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    justCopied = false
                }
            } label: {
                Label(justCopied ? "Copied" : "Copy", systemImage: justCopied ? "checkmark" : "doc.on.doc")
            }
            ShareLink(item: shownText) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        .onAppear {
            mode = record.cleanedText != nil ? .cleaned : .raw
        }
    }
}
