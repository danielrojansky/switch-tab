import ApplicationServices

// Undocumented system calls. Public APIs cannot map an accessibility window to its
// CGWindowID, reach windows on other Spaces, or raise a single window of another app.

@_silgen_name("_AXUIElementGetWindow")
func axGetWindowID(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

@_silgen_name("_AXUIElementCreateWithRemoteToken")
func axCreateWithRemoteToken(_ token: CFData) -> Unmanaged<AXUIElement>?

@_silgen_name("GetProcessForPID")
func processSerialNumber(forPID pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

@_silgen_name("_SLPSSetFrontProcessWithOptions")
func setFrontProcess(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ windowID: CGWindowID, _ mode: UInt32) -> CGError

@_silgen_name("SLPSPostEventRecordTo")
func postEventRecord(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ bytes: UnsafeMutablePointer<UInt8>) -> CGError

@_silgen_name("CGSMainConnectionID")
func cgsMainConnection() -> Int32

@_silgen_name("CGSCopySpacesForWindows")
func cgsCopySpacesForWindows(_ connection: Int32, _ mask: Int32, _ windowIDs: CFArray) -> Unmanaged<CFArray>?

@_silgen_name("CGSCopyManagedDisplaySpaces")
func cgsCopyManagedDisplaySpaces(_ connection: Int32) -> Unmanaged<CFArray>?

@_silgen_name("CGSSetSymbolicHotKeyEnabled")
func cgsSetSymbolicHotKeyEnabled(_ hotKey: Int32, _ enabled: UInt8) -> CGError

let frontProcessUserGenerated: UInt32 = 0x200

/// Native macOS shortcuts that must be switched off when Switch Tab takes over the same keys.
enum NativeHotKey {
    static let commandTab: Int32 = 1
    static let commandShiftTab: Int32 = 2
    static let commandKeyAboveTab: Int32 = 6

    static func set(commandTab: Bool, keyAboveTab: Bool) {
        _ = cgsSetSymbolicHotKeyEnabled(NativeHotKey.commandTab, commandTab ? 1 : 0)
        _ = cgsSetSymbolicHotKeyEnabled(NativeHotKey.commandShiftTab, commandTab ? 1 : 0)
        _ = cgsSetSymbolicHotKeyEnabled(NativeHotKey.commandKeyAboveTab, keyAboveTab ? 1 : 0)
    }

    static func restore() {
        set(commandTab: true, keyAboveTab: true)
    }
}
