import ApplicationServices

// Undocumented system calls. Public APIs cannot map an accessibility window to its
// CGWindowID, nor bring a single window of another app to the front.

@_silgen_name("_AXUIElementGetWindow")
func axGetWindowID(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

@_silgen_name("GetProcessForPID")
func processSerialNumber(forPID pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

@_silgen_name("_SLPSSetFrontProcessWithOptions")
func setFrontProcess(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ windowID: CGWindowID, _ mode: UInt32) -> CGError

let frontProcessUserGenerated: UInt32 = 0x200
