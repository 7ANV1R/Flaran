import AppKit
import FlaranKit
import SwiftUI

/// A session's log, shown in place inside the menu bar panel.
struct LogPage: View {
    let session: FlutterSession
    let back: () -> Void
    @State private var errorsOnly = false
    @State private var copied: String?

    var body: some View {
        let errors = session.log.lines.filter(\.isError)
        let lines = errorsOnly ? errors : session.log.lines
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ActionButton(.chevronLeft, help: "Back", action: back)
                VStack(alignment: .leading, spacing: 0) {
                    Text(session.projectDir.lastPathComponent).font(.system(size: 14, weight: .semibold))
                    Text("\(session.device.name) · \(session.state.summary)")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Picker("Show", selection: $errorsOnly) {
                    Text("All").tag(false)
                    Text(errors.isEmpty ? "Errors" : "Errors (\(errors.count))").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            ZStack {
                LogTextView(lines: lines, key: "\(session.id)-\(errorsOnly)")
                if lines.isEmpty {
                    Text(errorsOnly ? "No errors" : "No output yet").foregroundStyle(.secondary)
                }
            }
            .frame(height: 380)
            .clipShape(.rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
            HStack(spacing: 8) {
                copyButton("Copy Errors", lines: errors).disabled(errors.isEmpty)
                copyButton("Copy All", lines: session.log.lines).disabled(session.log.lines.isEmpty)
                if let copied { Text(copied).font(.system(size: 11)).foregroundStyle(.green).transition(.opacity) }
                Spacer()
                Button { session.log.clear() } label: { Label { Text("Clear") } icon: { Icon(.trash, size: 13) } }
                    .buttonStyle(.glass).controlSize(.small)
            }
        }
        .onAppear { session.log.markSeen() }
        .onChange(of: session.log.unseenErrors) { _, unseen in if unseen { session.log.markSeen() } }
    }

    private func copyButton(_ title: String, lines: [LogLine]) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(lines.map(\.text).joined(separator: "\n"), forType: .string)
            withAnimation { copied = "Copied \(lines.count) line\(lines.count == 1 ? "" : "s")" }
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation { copied = nil }
            }
        } label: {
            Label { Text(title) } icon: { Icon(.copy, size: 13) }
        }
        .buttonStyle(.glass).controlSize(.small)
    }
}

/// NSTextView rather than SwiftUI Text: selection across lines and fast appends for big logs.
struct LogTextView: NSViewRepresentable {
    let lines: [LogLine]
    /// Changes when the session or filter changes, forcing a full redraw.
    let key: String

    final class Coordinator {
        var key = ""
        var firstID: Int?
        var lastID = -1
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let text = scroll.documentView as! NSTextView
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.textContainerInset = NSSize(width: 6, height: 6)
        text.backgroundColor = .textBackgroundColor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let text = scroll.documentView as! NSTextView
        guard let storage = text.textStorage else { return }
        let c = context.coordinator
        let atBottom = text.visibleRect.maxY >= text.bounds.maxY - 30

        // ponytail: a head trim (LogStore drops 1,000 lines at a time) redraws everything once;
        // delete the leading character range instead if that ever shows up in a profile.
        if c.key != key || lines.first?.id != c.firstID || (lines.last?.id ?? -1) < c.lastID {
            storage.setAttributedString(render(lines))
        } else {
            let new = lines.drop { $0.id <= c.lastID }
            if new.isEmpty { return }
            storage.append(render(new))
        }
        c.key = key
        c.firstID = lines.first?.id
        c.lastID = lines.last?.id ?? -1
        if atBottom { text.scrollToEndOfDocument(nil) }
    }

    private func render(_ lines: some Collection<LogLine>) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let result = NSMutableAttributedString()
        for line in lines {
            result.append(NSAttributedString(string: line.text + "\n", attributes: [
                .font: font,
                .foregroundColor: line.isError ? NSColor.systemRed : NSColor.textColor,
            ]))
        }
        return result
    }
}
