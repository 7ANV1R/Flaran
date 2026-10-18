#if DEBUG
import AppKit
import FlaranKit
import SwiftUI

/// README screenshots on a clean backdrop instead of the real desktop. Debug builds only:
///   FLARAN_SHOWCASE=home|devices|logs FLARAN_SHOWCASE_RECT=/tmp/rect .build/debug/Flaran
/// Demo projects, devices and runs (fake `flutter` scripts); writes the capture rect when ready.
/// scripts/screenshots.sh drives it.
@MainActor enum Showcase {
    static var scene: String? { ProcessInfo.processInfo.environment["FLARAN_SHOWCASE"] }

    static func makeModel() -> AppModel {
        let suite = "dev.rivnat.Flaran.showcase"
        UserDefaults().removePersistentDomain(forName: suite)
        return AppModel(defaults: UserDefaults(suiteName: suite)!, startDevices: false)
    }

    static func start(model: AppModel, statusBar: StatusBar, scene: String) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .aqua)
        model.devices.showcase(devices: devices, simulators: simulators, emulators: emulators)

        let shop = project("shop_app", script: shopScript(withError: scene == "logs"))
        let news = project("news_app", script: newsScript)
        var window: NSWindow?
        var mark = NSRect.zero
        window = backdrop { markFrame in
            mark = markFrame
            statusBar.showPanel(below: markFrame, rightEdge: window?.frame.maxX ?? .infinity)
        }

        Task {
            try? await Task.sleep(for: .seconds(1))
            switch scene {
            case "devices":
                model.run(shop, .defaultConfig, devices[0])
                try? await Task.sleep(for: .seconds(1))
                model.go(.devices(shop, .defaultConfig))
            case "logs":
                model.run(shop, .defaultConfig, devices[0])
                try? await Task.sleep(for: .seconds(0.5))
                model.sessions.first?.log.clear()  // drop the "$ <temp path>/flutter run" line; output starts at 1s
                try? await Task.sleep(for: .seconds(2))
                if let s = model.sessions.first { model.go(.logs(s.id)) }
            default:
                model.run(shop, .defaultConfig, devices[0])
                model.run(news, .defaultConfig, devices[1])
                model.selectedID = model.sessions.first?.id
            }
            try? await Task.sleep(for: .seconds(5))  // the blurred wallpaper takes a moment to first render
            if let window { writeRect(of: window, panel: statusBar.panelFrame, mark: mark) }
        }
    }

    // MARK: demo data

    static let devices = [
        DeviceInfo(id: "emulator-5554", name: "Pixel 9", platform: "android-arm64", isEmulator: true,
                   emulatorId: "Pixel_9", sdk: "Android 16 (API 36)"),
        DeviceInfo(id: "SIM-17-PRO", name: "iPhone 17 Pro", platform: "ios", isEmulator: true,
                   emulatorId: "apple_ios_simulator", sdk: "iOS 26.0 (simulator)"),
        DeviceInfo(id: "macos", name: "macOS", platform: "darwin"),
        DeviceInfo(id: "chrome", name: "Chrome", platform: "web-javascript"),
    ]
    static let simulators = [
        SimulatorInfo(id: "SIM-17", name: "iPhone 17", runtime: "iOS 26.0", isBooted: false),
        SimulatorInfo(id: "SIM-AIR", name: "iPad Air 11-inch (M3)", runtime: "iOS 26.0", isBooted: false),
    ]
    static let emulators = [
        EmulatorInfo(id: "Pixel_9_Pro", name: "Pixel 9 Pro", platformType: "android"),
        EmulatorInfo(id: "Pixel_Tablet", name: "Pixel Tablet", platformType: "android"),
    ]

    /// A throwaway Flutter project whose FVM-pinned `flutter` is a script speaking the daemon protocol.
    static func project(_ name: String, script: String) -> URL {
        let dir = URL(filePath: NSTemporaryDirectory()).appending(path: "flaran-showcase/\(name)")
        let bin = dir.appending(path: ".fvm/flutter_sdk/bin")
        try? FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try? "name: \(name)\n".write(to: dir.appending(path: "pubspec.yaml"), atomically: true, encoding: .utf8)
        let flutter = bin.appending(path: "flutter")
        try? ("#!/bin/bash\n" + script).write(to: flutter, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: flutter.path)
        return dir
    }

    static func shopScript(withError: Bool) -> String {
        var s = """
        sleep 1
        echo '[{"event":"app.start","params":{"appId":"A1"}}]'
        echo 'Launching lib/main.dart on Pixel 9 in debug mode...'
        echo 'Running Gradle task '"'"'assembleDebug'"'"'...'
        echo '✓ Built build/app/outputs/flutter-apk/app-debug.apk'
        echo 'Syncing files to device Pixel 9...'
        echo '[{"event":"app.started","params":{"appId":"A1"}}]'
        echo 'I/flutter ( 4821): Cart loaded: 3 items'
        echo 'I/flutter ( 4821): Checkout tapped'

        """
        if withError {
            s += """
            echo '══╡ EXCEPTION CAUGHT BY RENDERING LIBRARY ╞═════════════════════════════════'
            echo 'The following assertion was thrown during layout:'
            echo 'A RenderFlex overflowed by 42 pixels on the right.'
            echo 'The relevant error-causing widget was:'
            echo '  Row Row:file:///lib/cart/cart_item_tile.dart:38:12'
            echo '════════════════════════════════════════════════════════════════════════════'
            echo 'Reloaded 3 of 812 libraries in 412ms.'

            """
        }
        return s + "while read -r _; do :; done\n"
    }

    static let newsScript = """
    echo '[{"event":"app.start","params":{"appId":"B1"}}]'
    echo 'Launching lib/main.dart on iPhone 17 Pro in debug mode...'
    echo '[{"event":"app.progress","params":{"appId":"B1","id":"1","progressId":"xcode","message":"Running Xcode build...","finished":false}}]'
    while read -r _; do :; done

    """

    // MARK: backdrop

    /// A borderless window with a soft wallpaper and a minimal menu bar, just under the panel's level.
    static func backdrop(onMarkFrame: @escaping (NSRect) -> Void) -> NSWindow {
        let size = NSSize(width: 980, height: 660)
        let screen = NSScreen.main!.visibleFrame
        let window = NSWindow(contentRect: NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2,
                                                  width: size.width, height: size.height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Backdrop { local in
            // SwiftUI global coordinates are top-left within the window.
            let f = window.frame
            onMarkFrame(NSRect(x: f.minX + local.minX, y: f.maxY - local.maxY, width: local.width, height: local.height))
        })
        window.orderFrontRegardless()
        return window
    }

    /// Every scene captures the same top-right 720×620 pt of the backdrop, so the images line up
    /// (the panel always hangs from the same icon). `screencapture -R` takes x,y,w,h in points from the
    /// top-left of the main display.
    static func writeRect(of window: NSWindow, panel: NSRect, mark: NSRect) {
        guard let path = ProcessInfo.processInfo.environment["FLARAN_SHOWCASE_RECT"],
              let screenHeight = NSScreen.screens.first?.frame.height else { return }
        _ = (panel, mark)
        let w = window.frame
        let f = NSRect(x: w.maxX - 720, y: w.maxY - 620, width: 720, height: 620)
        let rect = "\(Int(f.minX)),\(Int(screenHeight - f.maxY)),\(Int(f.width)),\(Int(f.height))"
        try? rect.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

/// FLARAN_SHOWCASE_WALLPAPER=<image file> if set, otherwise soft blurred blues.
private struct Wallpaper: View {
    var body: some View {
        if let path = ProcessInfo.processInfo.environment["FLARAN_SHOWCASE_WALLPAPER"],
           let image = NSImage(contentsOfFile: (path as NSString).expandingTildeInPath) {
            Image(nsImage: image).resizable().scaledToFill().clipped()
        } else {
            blues
        }
    }

    private var blues: some View {
        ZStack {
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.55, 0], [1, 0],
                [0, 0.45], [0.5, 0.55], [1, 0.4],
                [0, 1], [0.45, 1], [1, 1],
            ], colors: [
                Color(red: 0.42, green: 0.62, blue: 0.98), Color(red: 0.55, green: 0.76, blue: 1.00), Color(red: 0.70, green: 0.86, blue: 1.00),
                Color(red: 0.30, green: 0.52, blue: 0.95), Color(red: 0.62, green: 0.82, blue: 1.00), Color(red: 0.45, green: 0.72, blue: 0.98),
                Color(red: 0.22, green: 0.42, blue: 0.88), Color(red: 0.40, green: 0.66, blue: 0.97), Color(red: 0.58, green: 0.84, blue: 1.00),
            ])
            Circle().fill(Color(red: 0.80, green: 0.93, blue: 1.00)).frame(width: 420).offset(x: 220, y: -160).blur(radius: 120)
            Circle().fill(Color(red: 0.36, green: 0.78, blue: 0.98)).frame(width: 360).offset(x: -260, y: 180).blur(radius: 110)
            Circle().fill(Color(red: 0.25, green: 0.45, blue: 0.95)).frame(width: 300).offset(x: 120, y: 260).blur(radius: 100)
        }
        .clipped()
    }
}

private struct Backdrop: View {
    let onMarkFrame: (CGRect) -> Void
    @State private var reported = false

    var body: some View {
        ZStack(alignment: .top) {
            Wallpaper()
            HStack(spacing: 14) {
                Spacer()
                Icon(.reload, size: 16)
                Icon(.restart, size: 16)
                Image(nsImage: menuBarIcon(errors: false)).renderingMode(.template)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.white.opacity(0.35), in: .rect(cornerRadius: 6))
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                        guard !reported else { return }
                        reported = true
                        onMarkFrame(frame)
                    }
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
                Image(systemName: "magnifyingglass")
                Image(systemName: "switch.2")
                Text("Mon 9:41").font(.system(size: 13, weight: .medium))
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.black.opacity(0.85))
            .padding(.horizontal, 16)
            .frame(height: 30)
            .background(.white.opacity(0.28))
        }
        .ignoresSafeArea()
    }
}
#endif
