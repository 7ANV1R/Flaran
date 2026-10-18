import FlaranKit
import SwiftUI

/// The panel under the Flaran menu bar icon. Sub-pages slide in place; nothing closes mid-flow.
struct PanelView: View {
    let model: AppModel
    /// Reports the panel's natural size so the window can follow it.
    let onSize: (CGSize) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            content
                .id(model.page)
                .transition(.asymmetric(
                    insertion: .move(edge: model.forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: model.forward ? .leading : .trailing).combined(with: .opacity)))
        }
        .padding(12)
        .frame(width: model.page.isLogs ? 580 : 360, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .clipShape(.rect(cornerRadius: 18))
        .fixedSize()
        .background { Button("Quit") { model.quit() }.keyboardShortcut("q").opacity(0) }  // ⌘Q on every page
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var content: some View {
        switch model.page {
        case .home: HomePage(model: model)
        case let .logs(id):
            if let session = model.sessions.first(where: { $0.id == id }) {
                LogPage(session: session) { model.go(.home) }
            } else {
                HomePage(model: model)
            }
        case .projects: ProjectsPage(model: model)
        case let .configs(project): ConfigsPage(model: model, project: project)
        case let .devices(project, config): DevicesPage(model: model, project: project, config: config)
        }
    }
}

private extension Page {
    var isLogs: Bool { if case .logs = self { true } else { false } }
}

// MARK: - Home

private struct HomePage: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(nsImage: menuBarIcon(errors: false)).renderingMode(.template)
                Text("Flaran").font(.system(size: 14, weight: .semibold))
                Spacer()
                if model.activeCount > 0 {
                    Text("\(model.activeCount) running")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.quaternary, in: .capsule)
                }
            }
            .padding(.horizontal, 8).padding(.bottom, 8)

            if model.flutterMissing {
                Notice(icon: .alert, tint: .orange, title: "Flutter SDK not found",
                       detail: "Install Flutter or add it to your shell’s PATH, then reopen Flaran.")
            }

            if model.sessions.isEmpty && model.pendingBoots.isEmpty {
                EmptyState(model: model)
            } else {
                SectionHeader("Apps")
                CappedScroll(maxHeight: 380) {
                    ForEach(model.pendingBoots) { BootRow(model: model, boot: $0) }
                    ForEach(model.sessions) { session in
                        SessionRow(model: model, session: session)
                    }
                }
                Divider().padding(.vertical, 6)
                if let quick = model.quickRun {
                    Row(action: { model.run(quick.project, quick.config, quick.device) }) {
                        RowIcon(.play, tint: .green)
                        Titled(title: "Run \(quick.project.lastPathComponent)",
                               subtitle: detail(quick.config, quick.device))
                    }
                }
                Row(action: { model.go(.projects) }) {
                    RowIcon(.folder, tint: .blue)
                    Text("Run a Project…")
                    Spacer()
                    Icon(.chevronRight, size: 14).foregroundStyle(.tertiary)
                }
            }

            Divider().padding(.vertical, 6)
            HStack(spacing: 10) {
                RowIcon(.command, tint: .secondary)
                Titled(title: "Global Shortcuts", subtitle: "⌃⌥R reload · ⌃⌥⇧R restart")
                Spacer()
                Toggle("Global Shortcuts", isOn: Bindable(model).hotkeysEnabled)
                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            if let error = model.devices.lastError {
                Notice(icon: .alert, tint: .orange, title: error, detail: nil)
            }
            Row(action: { model.quit() }) {
                if model.isQuitting {
                    ProgressView().controlSize(.small).frame(width: 26, height: 26)
                    Text("Stopping apps…").foregroundStyle(.secondary)
                } else {
                    RowIcon(.power, tint: .secondary)
                    Text("Quit Flaran")
                    Spacer()
                    Text("⌘Q").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
            .disabled(model.isQuitting)
        }
    }

    private func detail(_ config: LaunchConfig, _ device: DeviceInfo) -> String {
        config == .defaultConfig ? device.name : "\(config.name) · \(device.name)"
    }
}

private struct EmptyState: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 10) {
            Icon(.play, size: 22)
                .foregroundStyle(.secondary)
                .frame(width: 48, height: 48)
                .background(.quaternary.opacity(0.6), in: .circle)
            VStack(spacing: 2) {
                Text("Nothing running").font(.system(size: 13, weight: .semibold))
                Text("Pick a project and a device to start.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let quick = model.quickRun {
                Button { model.run(quick.project, quick.config, quick.device) } label: {
                    Label("Run \(quick.project.lastPathComponent) on \(quick.device.name)", systemImage: "play.fill")
                        .lineLimit(1)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                Button("Something else…") { model.go(.projects) }
                    .buttonStyle(.glass)
            } else {
                Button("Run a Project…") { model.go(.projects) }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

/// One run: project on top, "device · status" below; actions on the right.
/// With several runs, a click picks which one reload and restart act on (the accent ring).
private struct SessionRow: View {
    let model: AppModel
    let session: FlutterSession

    var body: some View {
        let selectable = model.sessions.count > 1
        let selected = selectable && model.selected?.id == session.id
        Row(action: { model.selectedID = session.id }) {
            StatusBadge(session: session)
                .overlay { if selected { Circle().strokeBorder(Color.accentColor, lineWidth: 2).padding(-2) } }
            Titled(title: session.projectDir.lastPathComponent,
                   subtitle: "\(session.device.name) · \(statusText)",
                   subtitleColor: statusColor)
            Spacer(minLength: 6)
            HStack(spacing: 2) {
                if session.isActive {
                    ActionButton(.devtools, help: "Open DevTools") { model.openDevTools(session) }
                        .disabled(!session.canReload)
                    if session.state == .stopping {
                        ProgressView().controlSize(.small).frame(width: 28, height: 28)
                    } else {
                        ActionButton(.stop, help: "Stop") { Task { await session.stop() } }
                    }
                } else {
                    ActionButton(.play, help: "Run again") { model.runAgain(session) }
                    ActionButton(.close, help: "Remove") { model.dismiss(session) }
                }
                ActionButton(.logs, help: "Logs") { model.go(.logs(session.id)) }
                    .overlay(alignment: .topTrailing) {
                        if session.log.unseenErrors {
                            Circle().fill(.red).frame(width: 7, height: 7).offset(x: -3, y: 3)
                        }
                    }
            }
        }
        .help(selected ? "Reload and restart in the menu bar act on this app" : selectable ? "Click to make reload and restart act on this app" : "")
    }

    private var statusText: String {
        switch session.state {
        case .starting: session.progress ?? "Starting…"
        case .running where session.log.unseenErrors: "Errors in log"
        default: session.state.summary
        }
    }

    private var statusColor: Color {
        if case .failed = session.state { return .red }
        return session.state == .running && session.log.unseenErrors ? .red : .secondary
    }
}

private struct StatusBadge: View {
    let session: FlutterSession

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.16))
            switch session.state {
            case .starting, .reloading, .stopping:
                ProgressView().controlSize(.small)
            case .running:
                Circle().fill(color).frame(width: 9, height: 9)
                    .shadow(color: color.opacity(0.7), radius: 3)
            case .failed:
                Icon(.alert, size: 14).foregroundStyle(color)
            case .exited:
                Icon(.stop, size: 13).foregroundStyle(color)
            }
        }
        .frame(width: 28, height: 28)
    }

    private var color: Color {
        switch session.state {
        case .running: session.log.unseenErrors ? .red : .green
        case .starting, .reloading: .orange
        case .failed: .red
        case .stopping, .exited: .secondary
        }
    }
}

private struct BootRow: View {
    let model: AppModel
    let boot: PendingBoot

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill((boot.failure == nil ? Color.orange : .red).opacity(0.16))
                if boot.failure == nil {
                    ProgressView().controlSize(.small)
                } else {
                    Icon(.alert, size: 14).foregroundStyle(.red)
                }
            }
            .frame(width: 28, height: 28)
            Titled(title: boot.failure == nil ? "Booting \(boot.deviceName)…" : "Couldn’t boot \(boot.deviceName)",
                   subtitle: boot.failure ?? "Then runs \(boot.project.lastPathComponent)",
                   subtitleColor: boot.failure == nil ? .secondary : .red)
            Spacer(minLength: 6)
            ActionButton(.close, help: boot.failure == nil ? "Cancel" : "Dismiss") { model.cancelBoot(boot) }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
    }
}

// MARK: - Run a project

private struct ProjectsPage: View {
    let model: AppModel

    var body: some View {
        SubPage(title: "Run a Project", back: { model.go(.home) }) {
            if model.recentProjects.isEmpty {
                Text("No projects yet. Add your Flutter project folder to get started.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 6)
            } else {
                SectionHeader("Recent")
                ForEach(model.recentProjects, id: \.self) { project in
                    Row(action: { model.choose(project: project) }) {
                        RowIcon(.folder, tint: .blue)
                        Titled(title: project.lastPathComponent,
                               subtitle: (project.deletingLastPathComponent().path(percentEncoded: false) as NSString)
                                   .abbreviatingWithTildeInPath,
                               subtitleTruncation: .middle)
                        Spacer()
                        Icon(.chevronRight, size: 14).foregroundStyle(.tertiary)
                    }
                    .contextMenu { Button("Remove from Recents") { model.removeRecent(project) } }
                }
            }
            Divider().padding(.vertical, 6)
            Row(action: { model.openFolder() }) {
                RowIcon(.folderAdd, tint: .accentColor)
                Text("Open Folder…")
            }
        }
    }
}

private struct ConfigsPage: View {
    let model: AppModel
    let project: URL

    var body: some View {
        SubPage(title: project.lastPathComponent, back: { model.go(.projects) }) {
            SectionHeader("Launch Configuration")
            ForEach(loadLaunchConfigs(projectDir: project), id: \.self) { config in
                Row(action: { model.go(.devices(project, config)) }) {
                    Icon(.check, size: 14).foregroundStyle(Color.accentColor)
                        .opacity(config.name == model.lastConfigName(project) ? 1 : 0)
                    Titled(title: config.name, subtitle: configDetail(config))
                    Spacer()
                    Icon(.chevronRight, size: 14).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func configDetail(_ c: LaunchConfig) -> String {
        let mode = c.flutterMode?.capitalized ?? "Debug"
        guard let program = c.program else { return mode }
        return "\(mode) · \(URL(filePath: program).lastPathComponent)"
    }
}

private struct DevicesPage: View {
    let model: AppModel
    let project: URL
    let config: LaunchConfig

    var body: some View {
        let devices = model.devices
        SubPage(title: config == .defaultConfig ? "Choose a Device" : "\(config.name) · Choose a Device",
                subtitle: project.lastPathComponent,
                back: {
                    model.go(loadLaunchConfigs(projectDir: project).count == 1 ? .projects : .configs(project))
                }) {
            SectionHeader("Connected")
            if model.flutterMissing {
                Notice(icon: .alert, tint: .orange, title: "Flutter SDK not found",
                       detail: "Install Flutter or add it to your shell’s PATH, then reopen Flaran.")
            } else if let error = devices.lastError, devices.devices.isEmpty {
                Notice(icon: .alert, tint: .orange, title: error, detail: "Use Refresh Devices below to try again.")
            } else if !devices.isReady && devices.devices.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small).frame(width: 28, height: 28)
                    Text("Looking for devices…").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
            } else if devices.devices.isEmpty {
                Text("No devices connected. Start one below.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 6)
            }
            ForEach(devices.devices) { device in
                let running = model.session(for: project, on: device)
                Row(action: { model.run(project, config, device) }) {
                    RowIcon(icon(for: device), tint: .primary)
                    Titled(title: device.name, subtitle: caption(for: device))
                    Spacer()
                    if running != nil {
                        Tag("Restart", tint: .orange)
                    } else if device.id == model.lastDeviceID(project) {
                        Tag("Last used", tint: .secondary)
                    }
                }
                .help(running != nil ? "Already running here: stops it and runs again" : "Run on \(device.name)")
            }

            if !devices.offlineSimulators.isEmpty {
                SectionHeader("iOS Simulators", icon: .apple)
                ForEach(devices.offlineSimulators) { simulator in
                    let busy = devices.launching.contains(simulator.id) || model.isBooting(simulator.name)
                    Row(action: { model.bootAndRun(project, config, simulator) }) {
                        RowIcon(simulator.name.hasPrefix("iPad") ? .tablet : .phone, tint: .secondary)
                        Titled(title: simulator.name, subtitle: simulator.runtime)
                        Spacer()
                        if busy { ProgressView().controlSize(.small) } else { Tag("Boot & Run", tint: .secondary) }
                    }
                    .disabled(busy)
                }
            }
            if !devices.offlineEmulators.isEmpty {
                SectionHeader("Android Emulators", icon: .android)
                ForEach(devices.offlineEmulators) { emulator in
                    let busy = devices.launching.contains(emulator.id) || model.isBooting(emulator.name)
                    Row(action: { model.bootAndRun(project, config, emulator, coldBoot: false) }) {
                        RowIcon(.phone, tint: .secondary)
                        Titled(title: emulator.name, subtitle: "Emulator")
                        Spacer()
                        if busy {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Cold Boot") { model.bootAndRun(project, config, emulator, coldBoot: true) }
                                .buttonStyle(.borderless).font(.system(size: 11))
                                .help("Boot without the saved snapshot")
                            Tag("Boot & Run", tint: .secondary)
                        }
                    }
                    .disabled(busy)
                }
            }
            Divider().padding(.vertical, 6)
            Row(action: { devices.refresh() }) {
                RowIcon(.refresh, tint: .secondary)
                Text("Refresh Devices")
            }
        }
    }

    /// Phones show their OS version; desktop and web get a plain description instead of build strings.
    private func caption(for device: DeviceInfo) -> String {
        if device.platform.hasPrefix("web") { return "Web browser" }
        if device.platform.hasPrefix("darwin") { return "This Mac" }
        if device.platform.hasPrefix("linux") || device.platform.hasPrefix("windows") { return "Desktop" }
        return device.sdk ?? device.platform
    }

    private func icon(for device: DeviceInfo) -> Glyph {
        let p = device.platform
        if p.hasPrefix("web") { return .globe }
        if p.hasPrefix("android") || p == "ios" { return device.name.contains("iPad") ? .tablet : .phone }
        return .desktop
    }
}

// MARK: - Building blocks

/// A sub-page with a back button and a scrolling body.
private struct SubPage<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    let back: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                ActionButton(.chevronLeft, help: "Back", action: back)
                    .keyboardShortcut(.leftArrow, modifiers: [])
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary) }
                }
            }
            .padding(.bottom, 6)
            CappedScroll(maxHeight: 520) { content }
        }
    }
}

/// Scrolls only past `maxHeight`. It's given an explicit height: a self-sizing ScrollView inside
/// a self-sizing window recurses forever.
private struct CappedScroll<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) { content }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(max(contentHeight, 20), maxHeight))
    }
}

/// A full-width row with the hover highlight of the system menu bar panels.
struct Row<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) { label }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(hovering && isEnabled ? Color.primary.opacity(0.08) : .clear, in: .rect(cornerRadius: 10))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct RowIcon: View {
    let icon: Glyph
    let tint: Color
    init(_ icon: Glyph, tint: Color) {
        self.icon = icon
        self.tint = tint
    }

    var body: some View {
        Icon(icon, size: 16)
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background(tint.opacity(0.12), in: .circle)
    }
}

private struct Titled: View {
    let title: String
    var subtitle: String? = nil
    var subtitleColor: Color = .secondary
    var subtitleTruncation: Text.TruncationMode = .tail

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1)
            if let subtitle {
                Text(subtitle).font(.system(size: 11)).foregroundStyle(subtitleColor).lineLimit(1)
                    .truncationMode(subtitleTruncation)
            }
        }
    }
}

struct ActionButton: View {
    let icon: Glyph
    let help: String
    let action: () -> Void
    @State private var hovering = false

    init(_ icon: Glyph, help: String, action: @escaping () -> Void) {
        self.icon = icon
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Icon(icon, size: 15)
                .frame(width: 28, height: 28)
                .background(hovering ? Color.primary.opacity(0.1) : .clear, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { hovering = $0 }
        .help(help)
    }
}

private struct Tag: View {
    let text: String
    let tint: Color
    init(_ text: String, tint: Color) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(tint.opacity(0.12), in: .capsule)
    }
}

private struct SectionHeader: View {
    let text: String
    var icon: Glyph?
    init(_ text: String, icon: Glyph? = nil) {
        self.text = text
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Icon(icon, size: 12) }
            Text(text)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 2)
    }
}

private struct Notice: View {
    let icon: Glyph
    let tint: Color
    let title: String
    let detail: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Icon(icon, size: 16).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold))
                if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.1), in: .rect(cornerRadius: 10))
        .padding(.bottom, 6)
    }
}
