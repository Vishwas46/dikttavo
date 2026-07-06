import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DictationRecord.createdAt, order: .reverse) private var records: [DictationRecord]
    @State private var confirmClearAll = false

    var body: some View {
        Group {
            if records.isEmpty {
                ContentUnavailableView(
                    "No dictations yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Finished dictations appear here. Everything stays on this iPhone.")
                )
            } else {
                List {
                    ForEach(records) { record in
                        NavigationLink {
                            HistoryDetailView(record: record)
                        } label: {
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
                    .onDelete { offsets in
                        for index in offsets {
                            context.delete(records[index])
                        }
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
                for record in records {
                    context.delete(record)
                }
            }
            Button("Cancel", role: .cancel) {}
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                UIPasteboard.general.string = shownText
                justCopied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    justCopied = false
                }
            } label: {
                Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
            }
            ShareLink(item: shownText) {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .onAppear {
            mode = record.cleanedText != nil ? .cleaned : .raw
        }
    }
}
