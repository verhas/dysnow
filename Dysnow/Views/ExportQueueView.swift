import AppKit
import SwiftUI

/// The files being saved, waiting, and done, above the status bar.
struct ExportQueueView: View {
    let queue: ExportQueue
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Saving Audio").font(.headline)
                if queue.waitingCount > 0 {
                    Text("\(queue.waitingCount) waiting").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear Done", action: queue.clearDone)
                    .disabled(!queue.hasDoneJobs)
                Button("Hide", systemImage: "chevron.down", action: close)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Hide the list; it is shown again from the status bar")
            }
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
            if queue.jobs.isEmpty {
                Text("Audio you save is listed here while it is made.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                List(queue.jobs) { job in
                    JobRow(job: job, remove: { queue.remove(job.id) })
                }
                .listStyle(.plain)
            }
        }
        .frame(height: 180)
        .background(.background.secondary)
    }
}

private struct JobRow: View {
    let job: ExportQueue.Job
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(job.voiceName), \(job.languageName): \(job.preview)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            state
            buttons
        }
        .padding(.vertical, 2)
        .contextMenu {
            if case .finished = job.state {
                Button("Show in Finder", action: reveal)
            }
            Button(removeTitle, action: remove)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch job.state {
        case .waiting: Image(systemName: "clock").foregroundStyle(.secondary)
        case .running: Image(systemName: "waveform").foregroundStyle(.tint)
        case .finished: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .cancelled: Image(systemName: "xmark.circle").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var state: some View {
        switch job.state {
        case .waiting:
            Text("Waiting").foregroundStyle(.secondary)
        case .running(let done):
            ProgressView(value: done).frame(width: 120)
            Text(done.formatted(.percent.precision(.fractionLength(0))))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        case .finished(let duration):
            Text("Saved, \(ExportQueue.format(duration))").foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).foregroundStyle(.red).lineLimit(1).help(message)
        case .cancelled:
            Text("Stopped").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        if case .finished = job.state {
            Button("Show in Finder", systemImage: "magnifyingglass", action: reveal)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Show in Finder")
        }
        Button(removeTitle, systemImage: job.state == .waiting || job.isDone ? "xmark" : "stop.circle",
               action: remove)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help(removeTitle)
    }

    private var removeTitle: String {
        switch job.state {
        case .waiting: "Take off the queue"
        case .running: "Stop making it"
        case .finished, .failed, .cancelled: "Remove from the list"
        }
    }

    private func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting([job.url])
    }
}
