import Foundation
import Testing
@testable import FlaranKit

@Test func parsesIOSSimulatorsOnly() {
    let json = """
    {"devices": {
      "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
        {"udid": "U1", "name": "iPhone 18 Pro", "state": "Shutdown", "isAvailable": true},
        {"udid": "U2", "name": "iPhone 17", "state": "Booted", "isAvailable": true},
        {"udid": "U3", "name": "Broken", "state": "Shutdown", "isAvailable": false}
      ],
      "com.apple.CoreSimulator.SimRuntime.watchOS-27-0": [
        {"udid": "W1", "name": "Apple Watch", "state": "Shutdown", "isAvailable": true}
      ]
    }}
    """
    let sims = parseSimulators(Data(json.utf8))
    #expect(sims.map(\.id) == ["U1", "U2"])
    #expect(sims[0].runtime == "iOS 27.0")
    #expect(sims[1].isBooted)
}

@Test func emulatorDevicesGetTheirAvdName() {
    let emulators = [EmulatorInfo(id: "Pixel_10_Pro", name: "Pixel 10 Pro", platformType: "android")]
    let raw = DeviceInfo(id: "emulator-5554", name: "sdk gphone16k arm64", platform: "android-arm64",
                         isEmulator: true, emulatorId: "Pixel_10_Pro")
    #expect(friendlyName(raw, emulators: emulators).name == "Pixel 10 Pro")
    let phone = DeviceInfo(id: "abc", name: "Rivnat's iPhone", platform: "ios")
    #expect(friendlyName(phone, emulators: emulators).name == "Rivnat's iPhone")
}
