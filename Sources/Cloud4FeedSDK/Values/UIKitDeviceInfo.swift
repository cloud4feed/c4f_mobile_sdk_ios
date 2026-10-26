#if canImport(UIKit) && !os(watchOS)
import UIKit
import Darwin
#if canImport(Network)
import Network
#endif
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif
#if canImport(CoreLocation)
import CoreLocation
#endif

/// DEVICE values on iOS (Android: `DeviceUtils` + the extras in `ExclusionRuleEvaluator`).
/// Read on the main thread. Not available on iOS: `is_roaming`, `low_memory`,
/// `available_memory_mb` and the storage keys (no value -> parameter skipped / rule sees "").
final class UIKitDeviceInfo: FoundationDeviceInfo {
    #if canImport(Network)
    private let pathMonitor = NWPathMonitor()
    private let pathLock = NSLock()
    private var currentPath: NWPath?
    #endif
    #if canImport(CoreLocation)
    private lazy var locationManager = CLLocationManager()
    #endif

    init() {
        super.init()
        #if canImport(Network)
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            self.pathLock.lock()
            self.currentPath = path
            self.pathLock.unlock()
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.cloud4feed.mobilesdk.network"))
        #endif
    }

    deinit {
        #if canImport(Network)
        pathMonitor.cancel()
        #endif
    }

    override func extraValues() -> [String: String] {
        var values: [String: String] = [:]
        let device = UIDevice.current

        if let vendorId = device.identifierForVendor?.uuidString {
            values["deviceID"] = vendorId
        }
        values["deviceModel"] = Self.hardwareModel()
        values["device"] = device.model

        let native = UIScreen.main.nativeBounds
        values["screenResolution"] = "\(Int(native.width))x\(Int(native.height))"
        values["deviceOrientation"] = Self.isLandscape() ? "landscape" : "portrait"

        addBattery(to: &values, device: device)
        addNetwork(to: &values)
        addSecurity(to: &values)
        addMemory(to: &values)
        addLocation(to: &values)
        return values
    }

    // MARK: Battery

    private func addBattery(to values: inout [String: String], device: UIDevice) {
        let wasMonitoring = device.isBatteryMonitoringEnabled
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel
        let state = device.batteryState
        device.isBatteryMonitoringEnabled = wasMonitoring

        if level >= 0 {
            values["battery_level"] = String(Int((level * 100).rounded()))
        }
        if state != .unknown {
            let charging = state == .charging || state == .full
            values["is_charging"] = charging ? "true" : "false"
            // iOS does not tell AC / USB / wireless apart.
            values["charge_type"] = charging ? "charging" : "none"
        }
    }

    // MARK: Network

    private func addNetwork(to values: inout [String: String]) {
        #if canImport(Network)
        pathLock.lock()
        let path = currentPath
        pathLock.unlock()
        guard let path = path else { return }

        let type: String
        if path.status != .satisfied {
            type = "NONE"
        } else if path.usesInterfaceType(.wifi) {
            type = "WIFI"
        } else if path.usesInterfaceType(.cellular) {
            type = "MOBILE"
        } else if path.usesInterfaceType(.wiredEthernet) {
            type = "ETHERNET"
        } else {
            type = "OTHER"
        }
        values["networkType"] = type
        values["is_wifi"] = type == "WIFI" ? "true" : "false"
        #endif
    }

    // MARK: Security

    private func addSecurity(to values: inout [String: String]) {
        #if canImport(LocalAuthentication)
        // Passcode / Face ID / Touch ID set up on the device.
        let secured = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        values["is_secure_screen"] = secured ? "true" : "false"
        values["screen_lock"] = secured ? "1" : "0"
        #endif
    }

    // MARK: Memory

    private func addMemory(to values: inout [String: String]) {
        values["total_memory_mb"] = String(ProcessInfo.processInfo.physicalMemory / 1_048_576)

        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        if result == KERN_SUCCESS {
            values["app_used_memory_mb"] = String(info.phys_footprint / 1_048_576)
        }
    }

    // MARK: Location

    /// Only when the app already has location permission. The SDK never asks for it.
    private func addLocation(to values: inout [String: String]) {
        #if canImport(CoreLocation)
        let status = locationManager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways,
              let location = locationManager.location else { return }
        values["latitude"] = String(location.coordinate.latitude)
        values["longitude"] = String(location.coordinate.longitude)
        values["location_accuracy"] = String(location.horizontalAccuracy)
        #endif
    }

    // MARK: Helpers

    /// Hardware identifier such as `iPhone15,2` (the simulator reports the simulated model).
    static func hardwareModel() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    private static func isLandscape() -> Bool {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        if let orientation = scene?.interfaceOrientation {
            return orientation.isLandscape
        }
        return UIDevice.current.orientation.isLandscape
    }
}
#endif
