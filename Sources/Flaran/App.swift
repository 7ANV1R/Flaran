import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    #if DEBUG
    let model = Showcase.scene == nil ? AppModel() : Showcase.makeModel()
    #else
    let model = AppModel()
    #endif
    private var statusBar: StatusBar?
    private var signalSources: [any DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusBar = StatusBar(model: model)
        self.statusBar = statusBar
        #if DEBUG
        if let scene = Showcase.scene { Showcase.start(model: model, statusBar: statusBar, scene: scene) }
        #endif
        // `kill`/`killall`/Ctrl-C skip applicationWillTerminate; still take our flutter processes down.
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [model] in
                MainActor.assumeIsolated { model.terminateAll() }
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    func applicationWillTerminate(_ notification: Notification) { model.terminateAll() }
}

@main
struct FlaranApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    // Everything lives in the menu bar (see StatusBar); no windows.
    var body: some Scene {
        Settings { EmptyView() }
    }
}
