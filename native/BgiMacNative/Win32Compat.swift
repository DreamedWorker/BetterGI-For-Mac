// Win32Compat — a small subset of user32 / gdi32 / kernel32 / ntdll implemented on macOS.
//
// Upstream BetterGI code (compiled unmodified) still calls a few dozen Win32 functions through
// P/Invoke. The .NET side redirects those DLL names to this library (MacWin32Compat.Install), so each
// function below is found by its Win32 name. Anything not listed here fails with an
// EntryPointNotFoundException that names the missing function.
//
// Conventions:
//   HWND          = macOS window number (CGWindowID)
//   coordinates   = "desktop pixels": global points * desktopScale (the scale of the game's display),
//                   which is the size captured frames have
//   virtual keys  = Win32 VK codes, translated with vkToMacKey

import AppKit
import CoreGraphics
import Foundation
import IOKit.pwr_mgt

/// Win32 virtual-key code -> macOS virtual key code (ANSI layout). Single source of truth; the .NET
/// side queries it through bgi_vk_to_keycode.
private let vkToMacKey: [Int32: UInt16] = [0x41: 0, 0x42: 11, 0x43: 8, 0x44: 2, 0x45: 14, 0x46: 3, 0x47: 5, 0x48: 4, 0x49: 34, 0x4A: 38, 0x4B: 40, 0x4C: 37, 0x4D: 46, 0x4E: 45, 0x4F: 31, 0x50: 35, 0x51: 12, 0x52: 15, 0x53: 1, 0x54: 17, 0x55: 32, 0x56: 9, 0x57: 13, 0x58: 7, 0x59: 16, 0x5A: 6, 0x30: 29, 0x31: 18, 0x32: 19, 0x33: 20, 0x34: 21, 0x35: 23, 0x36: 22, 0x37: 26, 0x38: 28, 0x39: 25, 0x08: 51, 0x09: 48, 0x0D: 36, 0x10: 56, 0xA0: 56, 0xA1: 60, 0x11: 59, 0xA2: 59, 0xA3: 62, 0x12: 58, 0xA4: 58, 0xA5: 61, 0x5B: 55, 0x5C: 54, 0x14: 57, 0x1B: 53, 0x20: 49, 0x21: 116, 0x22: 121, 0x23: 119, 0x24: 115, 0x25: 123, 0x26: 126, 0x27: 124, 0x28: 125, 0x2D: 114, 0x2E: 117, 0x70: 122, 0x71: 120, 0x72: 99, 0x73: 118, 0x74: 96, 0x75: 97, 0x76: 98, 0x77: 100, 0x78: 101, 0x79: 109, 0x7A: 103, 0x7B: 111, 0x60: 82, 0x61: 83, 0x62: 84, 0x63: 85, 0x64: 86, 0x65: 87, 0x66: 88, 0x67: 89, 0x68: 91, 0x69: 92, 0x6A: 67, 0x6B: 69, 0x6D: 78, 0x6E: 65, 0x6F: 75, 0xBA: 41, 0xBB: 24, 0xBC: 43, 0xBD: 27, 0xBE: 47, 0xBF: 44, 0xC0: 50, 0xDB: 33, 0xDC: 42, 0xDD: 30, 0xDE: 39]

private var desktopScale: Double = 1

/// Sets the points -> desktop pixels factor (the backing scale of the display showing the game).
@_cdecl("bgi_set_desktop_scale")
public func bgi_set_desktop_scale(_ scale: Double) {
    desktopScale = scale > 0 ? scale : 1
}

/// macOS key code for a Win32 virtual key, or -1 when there is none.
@_cdecl("bgi_vk_to_keycode")
public func bgi_vk_to_keycode(_ vk: Int32) -> Int32 {
    guard let code = vkToMacKey[vk] else { return -1 }
    return Int32(code)
}

private struct WinPoint { var x: Int32; var y: Int32 }
private struct WinRect { var left: Int32; var top: Int32; var right: Int32; var bottom: Int32 }

private func windowBounds(_ hWnd: UInt) -> CGRect? {
    guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(truncatingIfNeeded: hWnd)) as? [[String: Any]],
          let entry = list.first,
          let dict = entry[kCGWindowBounds as String] as? NSDictionary else { return nil }
    return CGRect(dictionaryRepresentation: dict as CFDictionary)
}

private func isMouseVk(_ vk: Int32) -> Int32? {
    switch vk {
    case 0x01: return 0
    case 0x02: return 1
    case 0x04: return 2
    case 0x05: return 3
    case 0x06: return 4
    default: return nil
    }
}

// MARK: user32

@_cdecl("GetForegroundWindow")
public func win32_GetForegroundWindow() -> UInt {
    var pid: Int32 = 0
    return UInt(bgi_frontmost_window(&pid))
}

@_cdecl("GetWindowThreadProcessId")
public func win32_GetWindowThreadProcessId(_ hWnd: UInt, _ processId: UnsafeMutablePointer<UInt32>?) -> UInt32 {
    var pid: Int32 = 0
    let alive = bgi_window_info(UInt32(truncatingIfNeeded: hWnd), nil, nil, nil, nil, nil, &pid, nil)
    processId?.pointee = alive != 0 ? UInt32(bitPattern: pid) : 0
    return alive != 0 ? UInt32(bitPattern: pid) : 0
}

@_cdecl("GetAsyncKeyState")
public func win32_GetAsyncKeyState(_ vk: Int32) -> Int16 {
    if let button = isMouseVk(vk) {
        let cgButton: CGMouseButton = button == 0 ? .left : button == 1 ? .right : .center
        return CGEventSource.buttonState(.combinedSessionState, button: cgButton) ? Int16(bitPattern: 0x8000) : 0
    }
    // generic modifiers also match their right-hand keys
    let extra: [Int32: UInt16] = [0x10: 60, 0x11: 62, 0x12: 61]
    var down = false
    if let code = vkToMacKey[vk] { down = CGEventSource.keyState(.combinedSessionState, key: code) }
    if !down, let code = extra[vk] { down = CGEventSource.keyState(.combinedSessionState, key: code) }
    return down ? Int16(bitPattern: 0x8000) : 0
}

@_cdecl("GetKeyState")
public func win32_GetKeyState(_ vk: Int32) -> Int16 { win32_GetAsyncKeyState(vk) }

@_cdecl("GetCursorPos")
public func win32_GetCursorPos(_ point: UnsafeMutableRawPointer?) -> Int32 {
    var x = 0.0, y = 0.0
    bgi_mouse_location(&x, &y)
    point?.storeBytes(of: WinPoint(x: Int32((x * desktopScale).rounded()), y: Int32((y * desktopScale).rounded())), as: WinPoint.self)
    return 1
}

@_cdecl("SetCursorPos")
public func win32_SetCursorPos(_ x: Int32, _ y: Int32) -> Int32 {
    bgi_mouse_move_to(Double(x) / desktopScale, Double(y) / desktopScale)
}

@_cdecl("IsWindow")
public func win32_IsWindow(_ hWnd: UInt) -> Int32 { windowBounds(hWnd) != nil ? 1 : 0 }

@_cdecl("IsWindowVisible")
public func win32_IsWindowVisible(_ hWnd: UInt) -> Int32 {
    var onScreen: Int32 = 0
    let alive = bgi_window_info(UInt32(truncatingIfNeeded: hWnd), nil, nil, nil, nil, nil, nil, &onScreen)
    return alive != 0 && onScreen != 0 ? 1 : 0
}

@_cdecl("IsWindowEnabled")
public func win32_IsWindowEnabled(_ hWnd: UInt) -> Int32 { win32_IsWindow(hWnd) }

@_cdecl("IsIconic")
public func win32_IsIconic(_ hWnd: UInt) -> Int32 {
    var onScreen: Int32 = 0
    let alive = bgi_window_info(UInt32(truncatingIfNeeded: hWnd), nil, nil, nil, nil, nil, nil, &onScreen)
    return alive != 0 && onScreen == 0 ? 1 : 0
}

@_cdecl("GetWindowRect")
public func win32_GetWindowRect(_ hWnd: UInt, _ rect: UnsafeMutableRawPointer?) -> Int32 {
    guard let bounds = windowBounds(hWnd) else { return 0 }
    let s = desktopScale
    rect?.storeBytes(of: WinRect(left: Int32((bounds.minX * s).rounded()), top: Int32((bounds.minY * s).rounded()),
                                 right: Int32((bounds.maxX * s).rounded()), bottom: Int32((bounds.maxY * s).rounded())), as: WinRect.self)
    return 1
}

/// 0 = SM_CXSCREEN, 1 = SM_CYSCREEN (main display), 76..79 = virtual screen x, y, width, height.
@_cdecl("GetSystemMetrics")
public func win32_GetSystemMetrics(_ index: Int32) -> Int32 {
    let main = CGDisplayBounds(CGMainDisplayID())
    var vx = 0.0, vy = 0.0, vw = 0.0, vh = 0.0
    bgi_virtual_desktop_bounds(&vx, &vy, &vw, &vh)
    let s = desktopScale
    switch index {
    case 0: return Int32((Double(main.width) * s).rounded())
    case 1: return Int32((Double(main.height) * s).rounded())
    case 76: return Int32((vx * s).rounded())
    case 77: return Int32((vy * s).rounded())
    case 78: return Int32((vw * s).rounded())
    case 79: return Int32((vh * s).rounded())
    case 80: return Int32(NSScreen.screens.count)
    default: return 0
    }
}

/// Device contexts do not exist; a constant token keeps SafeHandle wrappers valid.
@_cdecl("GetDC")
public func win32_GetDC(_ hWnd: UInt) -> UInt { 1 }

@_cdecl("ReleaseDC")
public func win32_ReleaseDC(_ hWnd: UInt, _ hdc: UInt) -> Int32 { 1 }

/// uMapType 0 (VK -> scan code) returns the macOS key code + 1 so that 0 still means "no translation".
@_cdecl("MapVirtualKey")
public func win32_MapVirtualKey(_ code: UInt32, _ mapType: UInt32) -> UInt32 {
    guard mapType == 0, let key = vkToMacKey[Int32(code)] else { return 0 }
    return UInt32(key) + 1
}

@_cdecl("MapVirtualKeyW")
public func win32_MapVirtualKeyW(_ code: UInt32, _ mapType: UInt32) -> UInt32 { win32_MapVirtualKey(code, mapType) }

private func postKey(_ hWnd: UInt, vk: Int32, down: Bool) {
    if let button = isMouseVk(vk) {
        _ = bgi_mouse_button(button, down ? 1 : 0)
        return
    }
    guard let code = vkToMacKey[vk] else { return }
    _ = bgi_key_event(code, down ? 1 : 0)
}

/// PostMessage for the input messages upstream's background channel sends. On Windows these reach the
/// game window even when it is not focused; here they are injected as ordinary input events, so they
/// act on the front-most window. A mouse message with client coordinates first moves the cursor there.
private func postMessage(_ hWnd: UInt, _ message: UInt32, _ wParam: Int, _ lParam: Int) -> Int32 {
    func moveIfNeeded() {
        guard lParam != 0, let bounds = windowBounds(hWnd) else { return }
        let x = Double(Int16(truncatingIfNeeded: lParam & 0xFFFF))
        let y = Double(Int16(truncatingIfNeeded: (lParam >> 16) & 0xFFFF))
        // client coordinates are relative to the game picture, which starts below the title bar
        _ = bgi_mouse_move_to(Double(bounds.minX) + x / desktopScale, Double(bounds.minY) + clientTopInset + y / desktopScale)
        usleep(10_000)
    }
    switch message {
    case 0x0100: postKey(hWnd, vk: Int32(truncatingIfNeeded: wParam), down: true)   // WM_KEYDOWN
    case 0x0101: postKey(hWnd, vk: Int32(truncatingIfNeeded: wParam), down: false)  // WM_KEYUP
    case 0x0201: moveIfNeeded(); _ = bgi_mouse_button(0, 1)                         // WM_LBUTTONDOWN
    case 0x0202: moveIfNeeded(); _ = bgi_mouse_button(0, 0)                         // WM_LBUTTONUP
    case 0x0204: moveIfNeeded(); _ = bgi_mouse_button(1, 1)                         // WM_RBUTTONDOWN
    case 0x0205: moveIfNeeded(); _ = bgi_mouse_button(1, 0)                         // WM_RBUTTONUP
    case 0x0207: moveIfNeeded(); _ = bgi_mouse_button(2, 1)                         // WM_MBUTTONDOWN
    case 0x0208: moveIfNeeded(); _ = bgi_mouse_button(2, 0)                         // WM_MBUTTONUP
    default: break // WM_CHAR, WM_ACTIVATE...: nothing to do, the key events already carry the character
    }
    return 1
}

private var clientTopInset: Double = 0

/// Height in points of the title bar above the game picture, used to place client-coordinate clicks.
@_cdecl("bgi_set_client_top_inset")
public func bgi_set_client_top_inset(_ points: Double) {
    clientTopInset = max(0, points)
}

@_cdecl("PostMessage")
public func win32_PostMessage(_ hWnd: UInt, _ message: UInt32, _ wParam: Int, _ lParam: Int) -> Int32 {
    postMessage(hWnd, message, wParam, lParam)
}

@_cdecl("PostMessageW")
public func win32_PostMessageW(_ hWnd: UInt, _ message: UInt32, _ wParam: Int, _ lParam: Int) -> Int32 {
    postMessage(hWnd, message, wParam, lParam)
}

// MARK: gdi32

/// HORZRES (8) / VERTRES (10) / DESKTOPVERTRES (117) / DESKTOPHORZRES (118): main display in desktop
/// pixels. LOGPIXELSX (88) / LOGPIXELSY (90): 96 * scale.
@_cdecl("GetDeviceCaps")
public func win32_GetDeviceCaps(_ hdc: UInt, _ index: Int32) -> Int32 {
    switch index {
    case 8, 118: return win32_GetSystemMetrics(0)
    case 10, 117: return win32_GetSystemMetrics(1)
    case 88, 90: return Int32((96 * desktopScale).rounded())
    default: return 0
    }
}

@_cdecl("DeleteDC")
public func win32_DeleteDC(_ hdc: UInt) -> Int32 { 1 }

/// Screen pixels cannot be read without a capture; CLR_INVALID tells the caller so.
@_cdecl("GetPixel")
public func win32_GetPixel(_ hdc: UInt, _ x: Int32, _ y: Int32) -> UInt32 { 0xFFFF_FFFF }

// MARK: kernel32 / ntdll

private var sleepAssertion: IOPMAssertionID = 0

/// ES_DISPLAY_REQUIRED (0x2) or ES_SYSTEM_REQUIRED (0x1) with ES_CONTINUOUS keeps the Mac awake;
/// ES_CONTINUOUS alone releases it.
@_cdecl("SetThreadExecutionState")
public func win32_SetThreadExecutionState(_ flags: UInt32) -> UInt32 {
    if sleepAssertion != 0 {
        IOPMAssertionRelease(sleepAssertion)
        sleepAssertion = 0
    }
    if flags & 0x3 != 0 {
        IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                    IOPMAssertionLevel(kIOPMAssertionLevelOn), "BetterGI task running" as CFString, &sleepAssertion)
    }
    return 0x8000_0000
}

/// Reports Windows 11 (10.0.22631) so that upstream's version checks take their modern paths.
@_cdecl("RtlGetVersion")
public func win32_RtlGetVersion(_ info: UnsafeMutableRawPointer?) -> Int32 {
    info?.storeBytes(of: UInt32(10), toByteOffset: 4, as: UInt32.self)
    info?.storeBytes(of: UInt32(0), toByteOffset: 8, as: UInt32.self)
    info?.storeBytes(of: UInt32(22631), toByteOffset: 12, as: UInt32.self)
    return 0
}
