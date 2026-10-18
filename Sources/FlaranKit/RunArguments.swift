/// `flutter run` argv in the same order as Flutter's own VS Code debug adapter:
/// tool flags, user toolArgs, --target program, user args.
public func runArguments(config: LaunchConfig, deviceId: String) -> [String] {
    var argv = ["run", "--machine", "-d", config.deviceId ?? deviceId]
    if let mode = config.flutterMode, mode != "debug" { argv.append("--\(mode)") }
    // No VM-service listener here, so errors must go to stdout as text (VS Code does the same for noDebug).
    argv.append("--dart-define=flutter.inspector.structuredErrors=false")
    argv += config.toolArgs ?? []
    if let program = config.program { argv += ["--target", program] }
    argv += config.args ?? []
    return argv
}
