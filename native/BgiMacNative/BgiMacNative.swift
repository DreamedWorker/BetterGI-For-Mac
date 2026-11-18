// BgiMacNative — macOS platform layer for BetterGI-Mac.
//
// Exposes a flat C ABI (all symbols prefixed `bgi_`) consumed from .NET via P/Invoke:
//   * permissions  : Screen Recording / Accessibility checks
//   * windows      : enumerate top-level windows so the user can pick the game window manually
//                    (the game runs under Wine via Yaagl, so it cannot be found by process name)
//   * capture      : ScreenCaptureKit stream of one window, latest frame copied out as BGRA
//   * input        : keyboard / mouse injection through CGEvent
//
// Coordinates: every window/mouse coordinate crossing this ABI is in global display *points*
// (origin top-left of the main display). Captured frames are in *pixels* (points * scale).
//
// Built with the Command Line Tools only (no Xcode needed): see build.sh.

import AppKit
import ApplicationServices
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit
import Security

// MARK: - Helpers

private func jsonCString(_ object: Any) -> UnsafeMutablePointer<CChar>? {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: []),
          let text = String(data: data, encoding: .utf8) else {
        return strdup("[]")
    }
    return strdup(text)
}

/// Frees a string returned by this library.
@_cdecl("bgi_free")
public func bgi_free(_ ptr: UnsafeMutableRawPointer?) {
    free(ptr)
}

// MARK: - Permissions

/// 1 if this process may record the screen (needed for capture and for reading window titles).
@_cdecl("bgi_has_screen_capture_access")
public func bgi_has_screen_capture_access() -> Int32 {
    CGPreflightScreenCaptureAccess() ? 1 : 0
}

/// Triggers the system Screen Recording prompt (shown at most once per app by macOS).
@_cdecl("bgi_request_screen_capture_access")
public func bgi_request_screen_capture_access() -> Int32 {
    CGRequestScreenCaptureAccess() ? 1 : 0
}

/// 1 if this process may post synthetic input events. `prompt` != 0 shows the system dialog.
@_cdecl("bgi_has_accessibility_access")
public func bgi_has_accessibility_access(_ prompt: Int32) -> Int32 {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let options = [key: prompt != 0] as CFDictionary
    return AXIsProcessTrustedWithOptions(options) ? 1 : 0
}

// MARK: - Window enumeration

private struct WindowSnapshot {
    let id: CGWindowID
    let pid: pid_t
    let owner: String
    let title: String
    let bounds: CGRect
    let layer: Int
    let onScreen: Bool
    let alpha: Double
}

private func snapshotWindows(onScreenOnly: Bool) -> [WindowSnapshot] {
    var options: CGWindowListOption = [.excludeDesktopElements]
    if onScreenOnly { options.insert(.optionOnScreenOnly) }
    guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    var result: [WindowSnapshot] = []
    for entry in list {
        guard let number = entry[kCGWindowNumber as String] as? NSNumber,
              let pidNumber = entry[kCGWindowOwnerPID as String] as? NSNumber,
              let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
            continue
        }
        result.append(WindowSnapshot(
            id: CGWindowID(number.uint32Value),
            pid: pid_t(pidNumber.int32Value),
            owner: entry[kCGWindowOwnerName as String] as? String ?? "",
            title: entry[kCGWindowName as String] as? String ?? "",
            bounds: bounds,
            layer: (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
            onScreen: (entry[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false,
            alpha: (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1))
    }
    return result
}

private func backingScale(for bounds: CGRect) -> Double {
    // NSScreen frames are bottom-left based; convert the window centre to that space.
    guard let primary = NSScreen.screens.first else { return 1 }
    let centre = CGPoint(x: bounds.midX, y: primary.frame.height - bounds.midY)
    for screen in NSScreen.screens where screen.frame.contains(centre) {
        return Double(screen.backingScaleFactor)
    }
    return Double(primary.backingScaleFactor)
}

/// Returns a JSON array describing normal (layer 0) top-level windows, front-to-back.
/// Each item: id, pid, owner, title, executable, x, y, width, height, scale, onScreen.
/// The caller must release the string with `bgi_free`.
@_cdecl("bgi_list_windows")
public func bgi_list_windows(_ includeOffScreen: Int32) -> UnsafeMutablePointer<CChar>? {
    let ownPid = getpid()
    var items: [[String: Any]] = []
    for window in snapshotWindows(onScreenOnly: includeOffScreen == 0) {
        guard window.layer == 0, window.pid != ownPid,
              window.bounds.width >= 200, window.bounds.height >= 150 else {
            continue
        }
        let app = NSRunningApplication(processIdentifier: window.pid)
        items.append([
            "id": Int(window.id),
            "pid": Int(window.pid),
            "owner": window.owner,
            "title": window.title,
            "executable": app?.executableURL?.path ?? "",
            "x": Double(window.bounds.origin.x),
            "y": Double(window.bounds.origin.y),
            "width": Double(window.bounds.width),
            "height": Double(window.bounds.height),
            "scale": backingScale(for: window.bounds),
            "onScreen": window.onScreen,
        ])
    }
    return jsonCString(items)
}

/// Live geometry of one window. Returns 1 if the window still exists, 0 otherwise.
@_cdecl("bgi_window_info")
public func bgi_window_info(_ windowId: UInt32,
                            _ x: UnsafeMutablePointer<Double>?,
                            _ y: UnsafeMutablePointer<Double>?,
                            _ width: UnsafeMutablePointer<Double>?,
                            _ height: UnsafeMutablePointer<Double>?,
                            _ scale: UnsafeMutablePointer<Double>?,
                            _ pid: UnsafeMutablePointer<Int32>?,
                            _ onScreen: UnsafeMutablePointer<Int32>?) -> Int32 {
    // The window-list query only returns windows that are on screen; a minimised window, or one on
    // another Space, is looked up by its number instead so it is not mistaken for a closed one.
    var list = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowId) as? [[String: Any]] ?? []
    if list.isEmpty {
        var ids: [UnsafeRawPointer?] = [UnsafeRawPointer(bitPattern: UInt(windowId))]
        if let array = CFArrayCreate(nil, &ids, 1, nil),
           let described = CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]] {
            list = described
        }
    }
    guard let entry = list.first,
          let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
          let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
        return 0
    }
    x?.pointee = Double(bounds.origin.x)
    y?.pointee = Double(bounds.origin.y)
    width?.pointee = Double(bounds.width)
    height?.pointee = Double(bounds.height)
    scale?.pointee = backingScale(for: bounds)
    pid?.pointee = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
    onScreen?.pointee = ((entry[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false) ? 1 : 0
    return 1
}

/// 1 if the process owning `windowId` owns the front-most normal window on screen.
/// The comparison is by process, not by window: Wine keeps small helper windows (e.g. a 52x20 one)
/// stacked above the game window, so the game window itself is rarely first in the list.
/// Fully transparent overlay windows of other apps are ignored.
@_cdecl("bgi_window_is_frontmost")
public func bgi_window_is_frontmost(_ windowId: UInt32) -> Int32 {
    let windows = snapshotWindows(onScreenOnly: true)
    guard let target = windows.first(where: { $0.id == windowId }) else { return 0 }
    for window in windows where window.layer == 0 && window.alpha > 0.01 {
        return window.pid == target.pid ? 1 : 0
    }
    return 0
}

/// Brings the owning app forward and (when Accessibility is granted) raises the specific window.
@_cdecl("bgi_window_activate")
public func bgi_window_activate(_ windowId: UInt32) -> Int32 {
    guard let target = snapshotWindows(onScreenOnly: false).first(where: { $0.id == windowId }) else {
        return 0
    }
    if AXIsProcessTrusted() {
        let appElement = AXUIElementCreateApplication(target.pid)
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
           let axWindows = value as? [AXUIElement] {
            for axWindow in axWindows {
                var positionRef: CFTypeRef?
                var sizeRef: CFTypeRef?
                var position = CGPoint.zero
                var size = CGSize.zero
                guard AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &positionRef) == .success,
                      AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success,
                      let positionValue = positionRef, let sizeValue = sizeRef,
                      AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
                      AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
                    continue
                }
                // Match the AX window to the CG window by geometry (no public id bridge exists).
                if abs(position.x - target.bounds.origin.x) < 2, abs(position.y - target.bounds.origin.y) < 2,
                   abs(size.width - target.bounds.width) < 2, abs(size.height - target.bounds.height) < 2 {
                    AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                    AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
                    break
                }
            }
        }
    }
    guard let app = NSRunningApplication(processIdentifier: target.pid) else { return 0 }
    return app.activate(options: [.activateIgnoringOtherApps]) ? 1 : 0
}

// MARK: - Capture

private final class CaptureSession: NSObject, SCStreamOutput, SCStreamDelegate {
    private let lock = NSLock()
    private var stream: SCStream?
    private var filter: SCContentFilter?
    private let queue = DispatchQueue(label: "bgi.capture.frames", qos: .userInteractive)

    private var latest: CVPixelBuffer?
    private var sequence: UInt64 = 0
    private var stopped = true
    private var lastError = ""

    private(set) var windowId: CGWindowID = 0
    private var fps: Int32 = 30
    private var configuredSize = CGSize.zero

    var errorText: String {
        lock.lock(); defer { lock.unlock() }
        return lastError
    }

    private func setError(_ text: String) {
        lock.lock(); lastError = text; lock.unlock()
    }

    private static func findWindow(_ windowId: CGWindowID) -> (SCWindow?, String) {
        let semaphore = DispatchSemaphore(value: 0)
        var found: SCWindow?
        var message = ""
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { content, error in
            if let error = error {
                message = error.localizedDescription
            } else {
                found = content?.windows.first(where: { $0.windowID == windowId })
                if found == nil { message = "window \(windowId) not found" }
            }
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + 10) == .timedOut {
            return (nil, "timed out while querying shareable content")
        }
        return (found, message)
    }

    private func makeConfiguration(pixelWidth: Int, pixelHeight: Int) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = pixelWidth
        configuration.height = pixelHeight
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.showsCursor = false
        configuration.queueDepth = 3
        configuration.scalesToFit = true
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, fps)))
        if #available(macOS 13.0, *) {
            configuration.capturesAudio = false
        }
        if #available(macOS 14.0, *) {
            configuration.ignoreShadowsSingleWindow = true
            configuration.shouldBeOpaque = true
        }
        return configuration
    }

    func start(windowId: CGWindowID, fps: Int32) -> Int32 {
        stop()
        guard CGPreflightScreenCaptureAccess() else {
            setError("Screen Recording permission has not been granted")
            return -1
        }
        let (window, message) = CaptureSession.findWindow(windowId)
        guard let window = window else {
            setError(message)
            return -2
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        var scale = backingScale(for: window.frame)
        if #available(macOS 14.0, *) {
            scale = Double(filter.pointPixelScale)
        }
        self.fps = fps
        let pixelWidth = Int((Double(window.frame.width) * scale).rounded())
        let pixelHeight = Int((Double(window.frame.height) * scale).rounded())
        let configuration = makeConfiguration(pixelWidth: pixelWidth, pixelHeight: pixelHeight)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        } catch {
            setError("addStreamOutput failed: \(error.localizedDescription)")
            return -3
        }

        let semaphore = DispatchSemaphore(value: 0)
        var startError: Error?
        stream.startCapture { error in
            startError = error
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + 10) == .timedOut {
            setError("timed out while starting capture")
            return -4
        }
        if let startError = startError {
            setError("startCapture failed: \(startError.localizedDescription)")
            return -5
        }

        lock.lock()
        self.stream = stream
        self.filter = filter
        self.windowId = windowId
        self.configuredSize = CGSize(width: pixelWidth, height: pixelHeight)
        self.stopped = false
        self.lastError = ""
        lock.unlock()
        return 0
    }

    /// Re-sizes the stream output after the window was resized or moved to another display.
    func resize(pixelWidth: Int, pixelHeight: Int) -> Int32 {
        lock.lock()
        let stream = self.stream
        let unchanged = Int(configuredSize.width) == pixelWidth && Int(configuredSize.height) == pixelHeight
        lock.unlock()
        guard let stream = stream else { return -1 }
        if unchanged || pixelWidth <= 0 || pixelHeight <= 0 { return 0 }
        let configuration = makeConfiguration(pixelWidth: pixelWidth, pixelHeight: pixelHeight)
        let semaphore = DispatchSemaphore(value: 0)
        var updateError: Error?
        stream.updateConfiguration(configuration) { error in
            updateError = error
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5)
        if let updateError = updateError {
            setError("updateConfiguration failed: \(updateError.localizedDescription)")
            return -2
        }
        lock.lock()
        configuredSize = CGSize(width: pixelWidth, height: pixelHeight)
        lock.unlock()
        return 0
    }

    func stop() {
        lock.lock()
        let stream = self.stream
        self.stream = nil
        self.filter = nil
        self.latest = nil
        self.stopped = true
        lock.unlock()
        guard let stream = stream else { return }
        let semaphore = DispatchSemaphore(value: 0)
        stream.stopCapture { _ in semaphore.signal() }
        _ = semaphore.wait(timeout: .now() + 5)
    }

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return !stopped
    }

    // SCStreamOutput
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: statusRaw) == .complete,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return // idle / blank frames carry no new picture: keep the previous one
        }
        lock.lock()
        latest = pixelBuffer
        sequence &+= 1
        lock.unlock()
    }

    // SCStreamDelegate
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock()
        stopped = true
        lastError = "capture stopped: \(error.localizedDescription)"
        self.stream = nil
        lock.unlock()
    }

    /// Size in pixels of the newest frame, or zero when none has arrived yet.
    func latestSize() -> (Int, Int, UInt64) {
        lock.lock(); defer { lock.unlock() }
        guard let buffer = latest else { return (0, 0, sequence) }
        return (CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), sequence)
    }

    /// Copies the newest frame as tightly packed BGRA (stride = width * 4), skipping `cropTop`
    /// pixel rows (used to drop the macOS title bar). Returns the frame sequence, or 0 on failure.
    func copyLatest(into destination: UnsafeMutableRawPointer, capacity: Int, cropTop: Int,
                    width: UnsafeMutablePointer<Int32>?, height: UnsafeMutablePointer<Int32>?) -> UInt64 {
        lock.lock()
        let buffer = latest
        let currentSequence = sequence
        lock.unlock()
        guard let buffer = buffer else { return 0 }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return 0 }
        let fullWidth = CVPixelBufferGetWidth(buffer)
        let fullHeight = CVPixelBufferGetHeight(buffer)
        let sourceStride = CVPixelBufferGetBytesPerRow(buffer)
        let top = min(max(0, cropTop), max(0, fullHeight - 1))
        let outHeight = fullHeight - top
        let rowBytes = fullWidth * 4
        width?.pointee = Int32(fullWidth)
        height?.pointee = Int32(outHeight)
        guard capacity >= rowBytes * outHeight else { return 0 }
        if sourceStride == rowBytes {
            memcpy(destination, base + top * sourceStride, rowBytes * outHeight)
        } else {
            for row in 0..<outHeight {
                memcpy(destination + row * rowBytes, base + (row + top) * sourceStride, rowBytes)
            }
        }
        return currentSequence
    }
}

private let captureSession = CaptureSession()

/// Starts capturing one window. Returns 0 on success, negative on failure (see `bgi_capture_last_error`).
@_cdecl("bgi_capture_start")
public func bgi_capture_start(_ windowId: UInt32, _ fps: Int32) -> Int32 {
    captureSession.start(windowId: windowId, fps: fps)
}

@_cdecl("bgi_capture_stop")
public func bgi_capture_stop() {
    captureSession.stop()
}

@_cdecl("bgi_capture_is_running")
public func bgi_capture_is_running() -> Int32 {
    captureSession.isRunning ? 1 : 0
}

/// Adjusts the stream output size (pixels) after the window changed size.
@_cdecl("bgi_capture_resize")
public func bgi_capture_resize(_ pixelWidth: Int32, _ pixelHeight: Int32) -> Int32 {
    captureSession.resize(pixelWidth: Int(pixelWidth), pixelHeight: Int(pixelHeight))
}

/// Size (pixels, before any crop) and sequence number of the newest frame.
@_cdecl("bgi_capture_frame_size")
public func bgi_capture_frame_size(_ width: UnsafeMutablePointer<Int32>?,
                                   _ height: UnsafeMutablePointer<Int32>?) -> UInt64 {
    let (w, h, sequence) = captureSession.latestSize()
    width?.pointee = Int32(w)
    height?.pointee = Int32(h)
    return sequence
}

/// Copies the newest frame (BGRA, stride = width*4) minus `cropTop` rows. Returns its sequence or 0.
@_cdecl("bgi_capture_copy_frame")
public func bgi_capture_copy_frame(_ destination: UnsafeMutableRawPointer?, _ capacity: Int64, _ cropTop: Int32,
                                   _ width: UnsafeMutablePointer<Int32>?,
                                   _ height: UnsafeMutablePointer<Int32>?) -> UInt64 {
    guard let destination = destination else { return 0 }
    return captureSession.copyLatest(into: destination, capacity: Int(capacity), cropTop: Int(cropTop),
                                     width: width, height: height)
}

/// Last capture error message; release with `bgi_free`.
@_cdecl("bgi_capture_last_error")
public func bgi_capture_last_error() -> UnsafeMutablePointer<CChar>? {
    strdup(captureSession.errorText)
}

// MARK: - Input

private final class InputState {
    static let shared = InputState()
    let lock = NSLock()
    let source = CGEventSource(stateID: .hidSystemState)
    var flags: CGEventFlags = []
    var buttonsDown: Set<Int32> = []

    // macOS virtual key codes of the modifier keys
    static let modifierFlags: [CGKeyCode: CGEventFlags] = [
        56: .maskShift, 60: .maskShift,
        59: .maskControl, 62: .maskControl,
        58: .maskAlternate, 61: .maskAlternate,
        55: .maskCommand, 54: .maskCommand,
    ]
}

private func currentMouseLocation() -> CGPoint {
    CGEvent(source: nil)?.location ?? .zero
}

/// Posts a key down (`down` != 0) or key up for a macOS virtual key code.
@_cdecl("bgi_key_event")
public func bgi_key_event(_ keyCode: UInt16, _ down: Int32) -> Int32 {
    let state = InputState.shared
    state.lock.lock()
    defer { state.lock.unlock() }
    if let flag = InputState.modifierFlags[keyCode] {
        if down != 0 { state.flags.insert(flag) } else { state.flags.remove(flag) }
    }
    guard let event = CGEvent(keyboardEventSource: state.source, virtualKey: keyCode, keyDown: down != 0) else {
        return 0
    }
    event.flags = state.flags
    event.post(tap: .cghidEventTap)
    return 1
}

/// 1 if the physical/virtual key is currently held (used for hotkey polling).
@_cdecl("bgi_key_is_down")
public func bgi_key_is_down(_ keyCode: UInt16) -> Int32 {
    CGEventSource.keyState(.combinedSessionState, key: keyCode) ? 1 : 0
}

private func mouseMoveType(_ state: InputState) -> (CGEventType, CGMouseButton) {
    if state.buttonsDown.contains(0) { return (.leftMouseDragged, .left) }
    if state.buttonsDown.contains(1) { return (.rightMouseDragged, .right) }
    if state.buttonsDown.contains(2) { return (.otherMouseDragged, .center) }
    return (.mouseMoved, .left)
}

/// Moves the cursor to an absolute position in global display points.
@_cdecl("bgi_mouse_move_to")
public func bgi_mouse_move_to(_ x: Double, _ y: Double) -> Int32 {
    let state = InputState.shared
    state.lock.lock()
    defer { state.lock.unlock() }
    let (type, button) = mouseMoveType(state)
    let target = CGPoint(x: x, y: y)
    let previous = currentMouseLocation()
    guard let event = CGEvent(mouseEventSource: state.source, mouseType: type,
                              mouseCursorPosition: target, mouseButton: button) else {
        return 0
    }
    event.setIntegerValueField(.mouseEventDeltaX, value: Int64((target.x - previous.x).rounded()))
    event.setIntegerValueField(.mouseEventDeltaY, value: Int64((target.y - previous.y).rounded()))
    event.flags = state.flags
    event.post(tap: .cghidEventTap)
    return 1
}

/// Relative mouse movement (camera control). Deltas are written to the event so that apps reading
/// raw deltas while the cursor is captured (Wine's macdrv in mouse-look mode) still see the motion.
@_cdecl("bgi_mouse_move_by")
public func bgi_mouse_move_by(_ dx: Int32, _ dy: Int32) -> Int32 {
    let state = InputState.shared
    state.lock.lock()
    defer { state.lock.unlock() }
    let (type, button) = mouseMoveType(state)
    let previous = currentMouseLocation()
    let target = CGPoint(x: previous.x + CGFloat(dx), y: previous.y + CGFloat(dy))
    guard let event = CGEvent(mouseEventSource: state.source, mouseType: type,
                              mouseCursorPosition: target, mouseButton: button) else {
        return 0
    }
    event.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx))
    event.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy))
    event.flags = state.flags
    event.post(tap: .cghidEventTap)
    return 1
}

/// Presses or releases a mouse button at the current cursor position.
/// button: 0 = left, 1 = right, 2 = middle, 3 = X1, 4 = X2.
@_cdecl("bgi_mouse_button")
public func bgi_mouse_button(_ button: Int32, _ down: Int32) -> Int32 {
    let state = InputState.shared
    state.lock.lock()
    defer { state.lock.unlock() }
    let type: CGEventType
    let cgButton: CGMouseButton
    switch button {
    case 0:
        type = down != 0 ? .leftMouseDown : .leftMouseUp
        cgButton = .left
    case 1:
        type = down != 0 ? .rightMouseDown : .rightMouseUp
        cgButton = .right
    default:
        type = down != 0 ? .otherMouseDown : .otherMouseUp
        cgButton = .center
    }
    guard let event = CGEvent(mouseEventSource: state.source, mouseType: type,
                              mouseCursorPosition: currentMouseLocation(), mouseButton: cgButton) else {
        return 0
    }
    if button > 2 {
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
    }
    event.setIntegerValueField(.mouseEventClickState, value: 1)
    event.flags = state.flags
    if down != 0 { state.buttonsDown.insert(button) } else { state.buttonsDown.remove(button) }
    event.post(tap: .cghidEventTap)
    return 1
}

/// Vertical wheel scroll; positive = away from the user (scroll up), in wheel notches.
@_cdecl("bgi_mouse_scroll")
public func bgi_mouse_scroll(_ clicks: Int32) -> Int32 {
    let state = InputState.shared
    guard let event = CGEvent(scrollWheelEvent2Source: state.source, units: .line,
                              wheelCount: 1, wheel1: clicks, wheel2: 0, wheel3: 0) else {
        return 0
    }
    event.post(tap: .cghidEventTap)
    return 1
}

/// Current cursor position in global display points.
@_cdecl("bgi_mouse_location")
public func bgi_mouse_location(_ x: UnsafeMutablePointer<Double>?, _ y: UnsafeMutablePointer<Double>?) {
    let location = currentMouseLocation()
    x?.pointee = Double(location.x)
    y?.pointee = Double(location.y)
}

/// Releases every modifier and mouse button this library still holds down.
@_cdecl("bgi_input_release_all")
public func bgi_input_release_all() {
    let state = InputState.shared
    state.lock.lock()
    let buttons = state.buttonsDown
    let flags = state.flags
    state.lock.unlock()
    for button in buttons {
        _ = bgi_mouse_button(button, 0)
    }
    for (keyCode, flag) in InputState.modifierFlags where flags.contains(flag) {
        _ = bgi_key_event(keyCode, 0)
    }
}

/// Types text as Unicode key events (independent of the keyboard layout). `text` is UTF-16.
@_cdecl("bgi_type_text")
public func bgi_type_text(_ text: UnsafePointer<UInt16>?, _ length: Int32) -> Int32 {
    guard let text = text, length > 0 else { return 0 }
    let state = InputState.shared
    // One event pair per UTF-16 unit keeps apps that only read the first character working.
    for index in 0..<Int(length) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: state.source, virtualKey: 0, keyDown: down) else { return 0 }
            event.flags = []
            event.keyboardSetUnicodeString(stringLength: 1, unicodeString: text + index)
            event.post(tap: .cghidEventTap)
        }
        usleep(2000)
    }
    return 1
}

// MARK: - Displays

/// Size in points of the main display (the one whose top-left is the global origin).
@_cdecl("bgi_main_display_size")
public func bgi_main_display_size(_ width: UnsafeMutablePointer<Double>?, _ height: UnsafeMutablePointer<Double>?) {
    let bounds = CGDisplayBounds(CGMainDisplayID())
    width?.pointee = Double(bounds.width)
    height?.pointee = Double(bounds.height)
}

/// Bounding box in points of all active displays (the "virtual desktop").
@_cdecl("bgi_virtual_desktop_bounds")
public func bgi_virtual_desktop_bounds(_ x: UnsafeMutablePointer<Double>?, _ y: UnsafeMutablePointer<Double>?,
                                       _ width: UnsafeMutablePointer<Double>?, _ height: UnsafeMutablePointer<Double>?) {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &displays, &count)
    var union = CGRect.null
    for display in displays.prefix(Int(count)) {
        union = union.union(CGDisplayBounds(display))
    }
    if union.isNull { union = CGDisplayBounds(CGMainDisplayID()) }
    x?.pointee = Double(union.origin.x)
    y?.pointee = Double(union.origin.y)
    width?.pointee = Double(union.width)
    height?.pointee = Double(union.height)
}

/// Window number and owning pid of the front-most normal window (0 when none).
@_cdecl("bgi_frontmost_window")
public func bgi_frontmost_window(_ pid: UnsafeMutablePointer<Int32>?) -> UInt32 {
    for window in snapshotWindows(onScreenOnly: true) where window.layer == 0 && window.alpha > 0.01 {
        pid?.pointee = window.pid
        return window.id
    }
    pid?.pointee = 0
    return 0
}

/// Minimises (1) or restores (0) the window through Accessibility. Returns 1 on success.
@_cdecl("bgi_window_set_minimized")
public func bgi_window_set_minimized(_ windowId: UInt32, _ minimized: Int32) -> Int32 {
    guard AXIsProcessTrusted(),
          let target = snapshotWindows(onScreenOnly: false).first(where: { $0.id == windowId }) else {
        return 0
    }
    let appElement = AXUIElementCreateApplication(target.pid)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
          let axWindows = value as? [AXUIElement] else {
        return 0
    }
    var done: Int32 = 0
    for axWindow in axWindows {
        // A process usually has one real window; apply to all of them rather than guess by geometry
        // (a minimised window reports no usable geometry).
        let flag: CFBoolean = minimized != 0 ? kCFBooleanTrue : kCFBooleanFalse
        if AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, flag) == .success {
            done = 1
        }
    }
    return done
}

// MARK: - Keychain

private func keychainQuery(_ service: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
}

/// Stores (or replaces) a generic password for `service` in the login keychain. Returns 1 on success.
@_cdecl("bgi_keychain_set")
public func bgi_keychain_set(_ service: UnsafePointer<CChar>?, _ account: UnsafePointer<CChar>?,
                             _ secret: UnsafePointer<CChar>?) -> Int32 {
    guard let service = service, let account = account, let secret = secret else { return 0 }
    let serviceName = String(cString: service)
    SecItemDelete(keychainQuery(serviceName) as CFDictionary)
    var item = keychainQuery(serviceName)
    item[kSecAttrAccount as String] = String(cString: account)
    item[kSecValueData as String] = Data(String(cString: secret).utf8)
    return SecItemAdd(item as CFDictionary, nil) == errSecSuccess ? 1 : 0
}

/// Reads the entry for `service` as JSON {"account": "...", "secret": "..."}; nil when absent. Free with `bgi_free`.
@_cdecl("bgi_keychain_get")
public func bgi_keychain_get(_ service: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    guard let service = service else { return nil }
    var query = keychainQuery(String(cString: service))
    query[kSecReturnAttributes as String] = true
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
          let item = result as? [String: Any],
          let data = item[kSecValueData as String] as? Data else {
        return nil
    }
    return jsonCString([
        "account": item[kSecAttrAccount as String] as? String ?? "",
        "secret": String(data: data, encoding: .utf8) ?? "",
    ])
}

@_cdecl("bgi_keychain_delete")
public func bgi_keychain_delete(_ service: UnsafePointer<CChar>?) -> Int32 {
    guard let service = service else { return 0 }
    let status = SecItemDelete(keychainQuery(String(cString: service)) as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound ? 1 : 0
}
