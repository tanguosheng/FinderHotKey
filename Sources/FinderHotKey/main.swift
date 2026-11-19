import AppKit
import Carbon
import ApplicationServices

// MARK: - Helpers

private let hotKeySignature: FourCharCode = 0x46484B59 // 'FHKY'

private enum HotKeyID: UInt32, CaseIterable {
    case openFinder = 1
    case minimizeFrontWindow = 2
    case toggleDesktop = 3

    var title: String {
        switch self {
        case .openFinder: return "打开访达"
        case .minimizeFrontWindow: return "最小化当前窗口"
        case .toggleDesktop: return "显示桌面"
        }
    }

    var defaultKeyCode: UInt32 {
        switch self {
        case .openFinder: return UInt32(kVK_ANSI_E)
        case .minimizeFrontWindow: return UInt32(kVK_Escape)
        case .toggleDesktop: return UInt32(kVK_ANSI_D)
        }
    }

    var defaultModifiers: UInt32 { UInt32(cmdKey) }
}

/// Per-feature enable flag and shortcut, persisted in the app's preferences.
private enum HotKeySettings {
    private static func key(_ id: HotKeyID, _ field: String) -> String {
        "hotkey.\(id.rawValue).\(field)"
    }

    static func isEnabled(_ id: HotKeyID) -> Bool {
        guard let number = UserDefaults.standard.object(forKey: key(id, "enabled")) as? NSNumber else {
            return true
        }
        return number.boolValue
    }

    static func setEnabled(_ enabled: Bool, for id: HotKeyID) {
        UserDefaults.standard.set(enabled, forKey: key(id, "enabled"))
    }

    static func keyCode(_ id: HotKeyID) -> UInt32 {
        (UserDefaults.standard.object(forKey: key(id, "keyCode")) as? NSNumber)?.uint32Value ?? id.defaultKeyCode
    }

    static func modifiers(_ id: HotKeyID) -> UInt32 {
        (UserDefaults.standard.object(forKey: key(id, "modifiers")) as? NSNumber)?.uint32Value ?? id.defaultModifiers
    }

    static func setShortcut(keyCode: UInt32, modifiers: UInt32, for id: HotKeyID) {
        UserDefaults.standard.set(keyCode, forKey: key(id, "keyCode"))
        UserDefaults.standard.set(modifiers, forKey: key(id, "modifiers"))
    }
}

/// General app preferences.
private enum AppSettings {
    private static let statusBarIconKey = "ui.showStatusBarIcon"
    private static let finderPathKey = "finder.openPath"

    /// The menu bar icon is shown unless the user turns it off.
    static var showsStatusBarIcon: Bool {
        guard let number = UserDefaults.standard.object(forKey: statusBarIconKey) as? NSNumber else {
            return true
        }
        return number.boolValue
    }

    static func setShowsStatusBarIcon(_ visible: Bool) {
        UserDefaults.standard.set(visible, forKey: statusBarIconKey)
    }

    /// Folder opened by the “打开访达” hot key. `nil` means the home folder.
    static var finderPath: String? {
        UserDefaults.standard.string(forKey: finderPathKey)
    }

    static func setFinderPath(_ path: String) {
        UserDefaults.standard.set(path, forKey: finderPathKey)
    }

    private static let toastHoldKey = "ui.toastHoldMilliseconds"
    private static let toastFadeKey = "ui.toastFadeMilliseconds"
    private static let toastVisibleKey = "ui.showToast"
    private static let toastBackgroundColorKey = "ui.toastBackgroundColor"
    private static let toastTextColorKey = "ui.toastTextColor"

    static let defaultToastHoldMilliseconds = 600
    static let defaultToastFadeMilliseconds = 200
    static let defaultToastBackgroundColor = NSColor(srgbRed: 0x4C / 255.0,
                                                    green: 0x4C / 255.0,
                                                    blue: 0x4C / 255.0,
                                                    alpha: 1)
    static let defaultToastTextColor = NSColor.white

    /// The trigger hint is shown unless the user turns it off.
    static var showsToast: Bool {
        guard let number = UserDefaults.standard.object(forKey: toastVisibleKey) as? NSNumber else {
            return true
        }
        return number.boolValue
    }

    static func setShowsToast(_ visible: Bool) {
        UserDefaults.standard.set(visible, forKey: toastVisibleKey)
    }

    static var toastBackgroundColor: NSColor {
        storedColor(forKey: toastBackgroundColorKey, fallback: defaultToastBackgroundColor)
    }

    static func setToastBackgroundColor(_ color: NSColor) {
        store(color, forKey: toastBackgroundColorKey)
    }

    static var toastTextColor: NSColor {
        storedColor(forKey: toastTextColorKey, fallback: defaultToastTextColor)
    }

    static func setToastTextColor(_ color: NSColor) {
        store(color, forKey: toastTextColorKey)
    }

    private static func storedColor(forKey key: String, fallback: NSColor) -> NSColor {
        guard let components = UserDefaults.standard.array(forKey: key) as? [Double],
              components.count == 4 else {
            return fallback
        }
        return NSColor(srgbRed: components[0],
                       green: components[1],
                       blue: components[2],
                       alpha: components[3])
    }

    private static func store(_ color: NSColor, forKey key: String) {
        guard let srgb = color.usingColorSpace(.sRGB) else { return }
        UserDefaults.standard.set([srgb.redComponent,
                                   srgb.greenComponent,
                                   srgb.blueComponent,
                                   srgb.alphaComponent],
                                  forKey: key)
    }

    /// How long the trigger hint stays fully visible, in milliseconds.
    static var toastHoldMilliseconds: Int {
        guard let number = UserDefaults.standard.object(forKey: toastHoldKey) as? NSNumber else {
            return defaultToastHoldMilliseconds
        }
        return min(5000, max(0, number.intValue))
    }

    static func setToastHoldMilliseconds(_ value: Int) {
        UserDefaults.standard.set(min(5000, max(0, value)), forKey: toastHoldKey)
    }

    /// Fade-out duration of the trigger hint, in milliseconds.
    static var toastFadeMilliseconds: Int {
        guard let number = UserDefaults.standard.object(forKey: toastFadeKey) as? NSNumber else {
            return defaultToastFadeMilliseconds
        }
        return min(5000, max(0, number.intValue))
    }

    static func setToastFadeMilliseconds(_ value: Int) {
        UserDefaults.standard.set(min(5000, max(0, value)), forKey: toastFadeKey)
    }

    private static let unminimizeActivatedAppKey = "behavior.unminimizeActivatedApp"

    /// Restore an app's minimized windows when it is activated while none of
    /// its windows are visible. Off by default.
    static var unminimizeActivatedApp: Bool {
        guard let number = UserDefaults.standard.object(forKey: unminimizeActivatedAppKey) as? NSNumber else {
            return false
        }
        return number.boolValue
    }

    static func setUnminimizeActivatedApp(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: unminimizeActivatedAppKey)
    }
}

private var hotKeyRefs: [EventHotKeyRef] = []
private var permissionAlertShown = false

private func isTrusted(prompt: Bool = false) -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

private func showPermissionAlertIfNeeded() {
    guard !permissionAlertShown else { return }
    permissionAlertShown = true
    DispatchQueue.main.async {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "FinderHotKey 需要辅助功能权限"
        alert.informativeText = "请在“系统设置 › 隐私与安全性 › 辅助功能”中勾选 FinderHotKey，然后重试快捷键。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Shortcut descriptions

private let functionKeyNames: [Int: String] = [
    kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
    kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
    kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
    kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
]

private func layoutCharacter(for keyCode: UInt32) -> String? {
    guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
          let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
        return nil
    }
    let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
    return data.withUnsafeBytes { raw -> String? in
        guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let status = UCKeyTranslate(
            layout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}

private func keyName(for keyCode: UInt32) -> String {
    switch Int(keyCode) {
    case kVK_Escape: return "esc"
    case kVK_Return: return "return"
    case kVK_ANSI_KeypadEnter: return "enter"
    case kVK_Tab: return "tab"
    case kVK_Space: return "space"
    case kVK_Delete: return "delete"
    case kVK_ForwardDelete: return "forward delete"
    case kVK_Home: return "home"
    case kVK_End: return "end"
    case kVK_PageUp: return "page up"
    case kVK_PageDown: return "page down"
    case kVK_LeftArrow: return "←"
    case kVK_RightArrow: return "→"
    case kVK_UpArrow: return "↑"
    case kVK_DownArrow: return "↓"
    default:
        if let name = functionKeyNames[Int(keyCode)] { return name }
        return layoutCharacter(for: keyCode)?.uppercased() ?? "键码 \(keyCode)"
    }
}

private func modifierSymbols(_ modifiers: UInt32) -> String {
    var symbols = ""
    if modifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
    if modifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
    if modifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
    if modifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
    return symbols
}

private func shortcutDescription(keyCode: UInt32, modifiers: UInt32) -> String {
    modifierSymbols(modifiers) + keyName(for: keyCode)
}

/// Shortcut label for the trigger hint: modifier glyphs and the key rendered in
/// one font, so the whole string stays visually even.
private func shortcutHUDText(keyCode: UInt32, modifiers: UInt32) -> String {
    let symbols = modifierSymbols(modifiers)
    let key = keyName(for: keyCode)
    return symbols.isEmpty ? key : "\(symbols) \(key)"
}

// MARK: - Finder

private var automationAlertShown = false

private func showAutomationAlertIfNeeded() {
    guard !automationAlertShown else { return }
    automationAlertShown = true
    DispatchQueue.main.async {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "FinderHotKey 需要控制“访达”的权限"
        alert.informativeText = "为了每次按快捷键都新开一个访达窗口，需要允许 FinderHotKey 自动控制“访达”。请在“系统设置 › 隐私与安全性 › 自动化”中勾选 FinderHotKey 下的“访达”，然后重试。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}

private func appleScriptStringLiteral(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

/// AppleScript runs serially off the main thread: the first run may wait for the
/// Automation permission prompt and must not block the UI.
private let finderScriptQueue = DispatchQueue(label: "local.tgs.finderhotkey.finder")

private func openFinder() {
    var isDirectory: ObjCBool = false
    let configuredPath = AppSettings.finderPath ?? NSHomeDirectory()
    // A previously chosen folder may have been moved or deleted.
    let path = FileManager.default.fileExists(atPath: configuredPath, isDirectory: &isDirectory) && isDirectory.boolValue
        ? configuredPath
        : NSHomeDirectory()

    let literalPath = appleScriptStringLiteral(path)

    finderScriptQueue.async {
        // `NSWorkspace.open` only activates an existing window for the same
        // folder, so ask Finder itself for a new window. Finder owns the
        // placement, so the window never moves after it appears.
        let source = """
        tell application "Finder"
            activate
            make new Finder window to (POSIX file "\(literalPath)" as alias)
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard let error = error else { return }
        // Only a permission denial is guaranteed to happen before any window is
        // created. Other failures may have already opened a window, and falling
        // back there would open the folder a second time.
        guard (error[NSAppleScript.errorNumber] as? Int) == -1743 else { return }
        showAutomationAlertIfNeeded()
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}

// MARK: - AX helpers

private func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
        return nil
    }
    return value
}

private func windowFrame(_ window: AXUIElement) -> CGRect? {
    guard let positionValue = copyAttribute(window, kAXPositionAttribute as String),
          let sizeValue = copyAttribute(window, kAXSizeAttribute as String),
          CFGetTypeID(positionValue) == AXValueGetTypeID(),
          CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
        return nil
    }
    var point = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(unsafeBitCast(positionValue, to: AXValue.self), .cgPoint, &point),
          AXValueGetValue(unsafeBitCast(sizeValue, to: AXValue.self), .cgSize, &size) else {
        return nil
    }
    return CGRect(origin: point, size: size)
}

private func framesMatch(_ a: CGRect, _ b: CGRect) -> Bool {
    abs(a.origin.x - b.origin.x) <= 3 &&
        abs(a.origin.y - b.origin.y) <= 3 &&
        abs(a.size.width - b.size.width) <= 3 &&
        abs(a.size.height - b.size.height) <= 3
}

private func isMinimized(_ window: AXUIElement) -> Bool {
    guard let value = copyAttribute(window, kAXMinimizedAttribute as String) else { return false }
    return (value as? Bool) ?? false
}

private struct OnScreenWindowInfo {
    let pid: pid_t
    let frame: CGRect
}

private struct DisplayBounds {
    let id: CGDirectDisplayID
    let bounds: CGRect
}

/// All normal on-screen windows in the current space, ordered front to back.
private func onScreenWindows() -> [OnScreenWindowInfo] {
    guard let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    var result: [OnScreenWindowInfo] = []
    for info in infos {
        guard let owner = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
              let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0,
              let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else {
            continue
        }
        result.append(OnScreenWindowInfo(pid: owner, frame: bounds))
    }
    return result
}

private func activeDisplays() -> [DisplayBounds] {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
    return ids.prefix(Int(count)).map { DisplayBounds(id: $0, bounds: CGDisplayBounds($0)) }
}

private func squaredDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = a.x - b.x
    let dy = a.y - b.y
    return dx * dx + dy * dy
}

private func displayID(for frame: CGRect, in displays: [DisplayBounds]) -> CGDirectDisplayID? {
    guard !displays.isEmpty else { return nil }

    var bestID: CGDirectDisplayID?
    var bestArea: CGFloat = 0
    for display in displays {
        let intersection = frame.intersection(display.bounds)
        guard !intersection.isNull else { continue }
        let area = intersection.width * intersection.height
        if area > bestArea {
            bestArea = area
            bestID = display.id
        }
    }
    if let bestID = bestID, bestArea > 0 {
        return bestID
    }

    let center = CGPoint(x: frame.midX, y: frame.midY)
    return displays.min { a, b in
        squaredDistance(CGPoint(x: a.bounds.midX, y: a.bounds.midY), center) <
            squaredDistance(CGPoint(x: b.bounds.midX, y: b.bounds.midY), center)
    }?.id
}

private func isFrontmost(_ pid: pid_t) -> Bool {
    NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
}

private func focusedFrame(of appElement: AXUIElement) -> CGRect? {
    guard let value = copyAttribute(appElement, kAXFocusedWindowAttribute as String),
          CFGetTypeID(value) == AXUIElementGetTypeID() else {
        return nil
    }
    return windowFrame(unsafeBitCast(value, to: AXUIElement.self))
}

/// Finds the window closest to the frame. The app is activated first, which can
/// make it wake from App Nap and can let Stage Manager finish moving the window,
/// so a few short retries are needed instead of a single query.
private func matchingWindow(in appElement: AXUIElement,
                            frame: CGRect,
                            display: CGDirectDisplayID?,
                            displays: [DisplayBounds],
                            isCancelled: () -> Bool) -> AXUIElement? {
    var nearest: AXUIElement?
    var nearestDistance = CGFloat.greatestFiniteMagnitude
    var candidatesOnDisplay = 0
    for attempt in 0..<5 {
        if isCancelled() { return nil }
        let windows = (copyAttribute(appElement, kAXWindowsAttribute as String) as? [AXUIElement]) ?? []
        var closest: AXUIElement?
        var closestDistance = CGFloat.greatestFiniteMagnitude
        var countOnDisplay = 0
        for window in windows {
            guard !isMinimized(window), let rect = windowFrame(window) else { continue }
            if framesMatch(rect, frame) {
                return window
            }
            guard displayID(for: rect, in: displays) == display else { continue }
            countOnDisplay += 1
            let distance = squaredDistance(CGPoint(x: rect.midX, y: rect.midY),
                                           CGPoint(x: frame.midX, y: frame.midY))
            if distance < closestDistance {
                closestDistance = distance
                closest = window
            }
        }
        nearest = closest
        nearestDistance = closestDistance
        candidatesOnDisplay = countOnDisplay
        if attempt < 4 {
            usleep(40_000)
        }
    }
    // The window may have moved slightly while its app was activating. Only use
    // the fallback when it is unambiguous, so a different window is never focused.
    if candidatesOnDisplay == 1 {
        return nearest
    }
    if let nearest = nearest, nearestDistance <= 200 * 200 {
        return nearest
    }
    return nil
}

private func focusWindow(pid: pid_t, frame: CGRect, isCancelled: () -> Bool) {
    guard !isCancelled() else { return }
    guard let app = NSRunningApplication(processIdentifier: pid) else { return }

    let appElement = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(appElement, 1.0)

    // Activate before querying AX: a background app (especially one on another
    // display) may be napping, so its window list can time out, and AX focus
    // changes only stick once the app is frontmost. NSRunningApplication
    // activation is asynchronous and can be ignored by the system, so also use
    // the AX frontmost attribute and wait for the switch to land.
    if app.activationPolicy == .regular, !isFrontmost(pid) {
        _ = app.activate(options: [])
        AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        let deadline = Date().addingTimeInterval(0.4)
        while !isFrontmost(pid) {
            if isCancelled() || Date() >= deadline { break }
            usleep(10_000)
        }
    }

    guard !isCancelled() else { return }
    let displays = activeDisplays()
    let targetDisplay = displayID(for: frame, in: displays)

    guard let target = matchingWindow(in: appElement,
                                      frame: frame,
                                      display: targetDisplay,
                                      displays: displays,
                                      isCancelled: isCancelled) else {
        return
    }
    let targetFrame = windowFrame(target) ?? frame

    // Retry briefly: activation is asynchronous and the window server may still
    // be completing the switch to the other display.
    for attempt in 0..<3 {
        if isCancelled() { return }
        AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)
        let status = AXUIElementSetAttributeValue(appElement,
                                                  kAXFocusedWindowAttribute as CFString,
                                                  target)
        if status == .success,
           let focused = focusedFrame(of: appElement),
           framesMatch(focused, targetFrame) {
            return
        }
        if attempt < 2 {
            usleep(40_000)
        }
    }
}

// MARK: - Cascade focus scheduling

/// Windows minimized a moment ago. A rapid second press must not pick the same
/// window again while its minimize animation is still on screen.
private final class MinimizedWindowStore {
    private struct Entry {
        let pid: pid_t
        let frame: CGRect
        let date: Date
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private let lifetime: TimeInterval = 1.5

    func record(pid: pid_t, frame: CGRect) {
        lock.lock()
        pruneLocked()
        entries.append(Entry(pid: pid, frame: frame, date: Date()))
        lock.unlock()
    }

    func contains(pid: pid_t, frame: CGRect) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        pruneLocked()
        return entries.contains { $0.pid == pid && framesMatch($0.frame, frame) }
    }

    /// True when this app had a window minimized by the cascade just now. Such a
    /// window belongs to the user's active Cmd+Esc gesture and must not be
    /// restored by the auto-unminimize feature.
    func hasRecentMinimization(pid: pid_t) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        pruneLocked()
        let cutoff = Date().addingTimeInterval(-restoreSuppression)
        return entries.contains { $0.pid == pid && $0.date > cutoff }
    }

    /// Kept short so switching back with Cmd+Tab right after minimizing still
    /// restores; the held-modifier guard covers the longer Cmd+Esc gesture.
    private let restoreSuppression: TimeInterval = 0.6

    private func pruneLocked() {
        let now = Date()
        entries.removeAll { now.timeIntervalSince($0.date) > lifetime }
    }
}

private let minimizedWindowStore = MinimizedWindowStore()

/// Front-to-back on-screen windows that can still take part in the cascade.
private func cascadeCandidates(limit: Int) -> [OnScreenWindowInfo] {
    var result: [OnScreenWindowInfo] = []
    for info in onScreenWindows() where info.pid != getpid() {
        if minimizedWindowStore.contains(pid: info.pid, frame: info.frame) { continue }
        result.append(info)
        if result.count == limit { break }
    }
    return result
}

/// Runs focus changes off the hot-key path so minimizing is immediate even when
/// the next window belongs to a napping app on another display.
private final class FocusScheduler {
    private let queue = DispatchQueue(label: "local.tgs.finderhotkey.focus", qos: .userInteractive)
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var pendingWork: DispatchWorkItem?
    private var expectedActivations: [pid_t: Date] = [:]
    private var activationObserver: NSObjectProtocol?

    init() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.applicationDidActivate(notification)
        }
    }

    deinit {
        if let activationObserver = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    /// Focuses the frontmost remaining window after a short quiet period. Rapid
    /// Cmd+Esc presses keep pushing this back, so intermediate apps never flash
    /// to the front. The target is read when the work runs, because presses in
    /// the meantime have already changed which window is frontmost.
    func scheduleFrontWindowFocus() {
        lock.lock()
        generation &+= 1
        let gen = generation
        pendingWork?.cancel()
        lock.unlock()

        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.isCurrent(gen) else { return }
            guard let target = cascadeCandidates(limit: 1).first else {
                self.finish(gen)
                return
            }
            // Mark only when we actually start activating, so a canceled focus
            // never masks a real app switch.
            self.markExpectedActivation(target.pid)
            focusWindow(pid: target.pid, frame: target.frame) { !self.isCurrent(gen) }
            self.finish(gen)
        }
        lock.lock()
        pendingWork = work
        lock.unlock()
        queue.asyncAfter(deadline: .now() + 0.16, execute: work)
    }

    func cancel() {
        lock.lock()
        generation &+= 1
        pendingWork?.cancel()
        pendingWork = nil
        lock.unlock()
    }

    private func isCurrent(_ gen: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == gen
    }

    private func finish(_ gen: UInt64) {
        lock.lock()
        if generation == gen {
            pendingWork = nil
        }
        lock.unlock()
    }

    private func pruneExpectedActivationsLocked() {
        let now = Date()
        expectedActivations = expectedActivations.filter { $0.value > now }
    }

    private func markExpectedActivation(_ pid: pid_t) {
        lock.lock()
        pruneExpectedActivationsLocked()
        expectedActivations[pid] = Date().addingTimeInterval(1.0)
        lock.unlock()
    }

    private func isExpectedActivation(_ pid: pid_t) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let deadline = expectedActivations[pid], deadline > Date() else {
            expectedActivations[pid] = nil
            return false
        }
        // Keep the entry until it expires: activating an app can emit more than
        // one notification, and both are ours.
        return true
    }

    /// True when the app was brought forward by the cascade itself rather than
    /// by the user switching to it.
    func wasActivatedByCascade(pid: pid_t) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        pruneExpectedActivationsLocked()
        return expectedActivations[pid] != nil
    }

    private func applicationDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        // Clicking the Finder desktop does not cancel the cascade.
        if app.bundleIdentifier == "com.apple.finder" { return }
        // This activation was requested by our own focus operation.
        if isExpectedActivation(app.processIdentifier) { return }

        // The user switched to another app: do not pull focus back later.
        cancel()
    }
}

private let focusScheduler = FocusScheduler()

// MARK: - Restore minimized windows on activation

/// Cmd+Tab only activates an app; if every window of that app is minimized the
/// switch appears to do nothing. This observer restores those windows once the
/// activation has landed. Finder is skipped because clicking the desktop also
/// activates it, and popping its windows up there would be surprising.
private final class ActivationUnminimizer {
    private let queue = DispatchQueue(label: "local.tgs.finderhotkey.unminimize", qos: .userInitiated)
    private var observer: NSObjectProtocol?

    init() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.applicationDidActivate(notification)
        }
    }

    deinit {
        if let observer = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    private func applicationDidActivate(_ notification: Notification) {
        guard AppSettings.unminimizeActivatedApp,
              isTrusted(),
              let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.processIdentifier != getpid(),
              app.activationPolicy == .regular,
              app.bundleIdentifier != "com.apple.finder",
              // Activations caused by the Cmd+Esc cascade are not a user switch.
              !focusScheduler.wasActivatedByCascade(pid: app.processIdentifier) else { return }
        let pid = app.processIdentifier
        // Let the switch finish before querying AX; unminimizing while the
        // activation is still in flight can be dropped by the app.
        queue.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.restoreIfNoVisibleWindow(pid: pid)
        }
    }

    /// While the hot key's modifiers are still down the user is in the middle of
    /// a Cmd+Esc cascade, and restoring would fight it. Cmd+Tab only activates
    /// the app after Command is released, so a real switch is not suppressed.
    private func gestureModifiersHeld() -> Bool {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        return flags.contains(.maskCommand) || flags.contains(.maskAlternate) || flags.contains(.maskControl)
    }

    private func restoreIfNoVisibleWindow(pid: pid_t) {
        // The user may have switched away again before this ran.
        guard AppSettings.unminimizeActivatedApp,
              !gestureModifiersHeld(),
              !minimizedWindowStore.hasRecentMinimization(pid: pid),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }

        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 1.0)
        guard let windows = copyAttribute(appElement, kAXWindowsAttribute as String) as? [AXUIElement],
              !windows.isEmpty else { return }

        var visibleCount = 0
        var minimized: [AXUIElement] = []
        for window in windows {
            if isMinimized(window) {
                minimized.append(window)
            } else {
                visibleCount += 1
            }
        }
        guard visibleCount == 0 else { return }
        for window in minimized {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
    }
}

private let activationUnminimizer = ActivationUnminimizer()

// MARK: - Minimize front window (Cmd + Esc)

private func resolveWindow(pid: pid_t, frame: CGRect) -> (window: AXUIElement, frame: CGRect)? {
    let appElement = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(appElement, 1.0)

    // The next cascade window is usually the app's own focused window; check it
    // first to avoid walking every window on the hot-key path.
    if let value = copyAttribute(appElement, kAXFocusedWindowAttribute as String),
       CFGetTypeID(value) == AXUIElementGetTypeID() {
        let focused = unsafeBitCast(value, to: AXUIElement.self)
        if !isMinimized(focused), let rect = windowFrame(focused), framesMatch(rect, frame) {
            return (focused, rect)
        }
    }

    let windows = (copyAttribute(appElement, kAXWindowsAttribute as String) as? [AXUIElement]) ?? []
    for window in windows {
        guard !isMinimized(window), let rect = windowFrame(window), framesMatch(rect, frame) else { continue }
        return (window, rect)
    }
    return nil
}

/// Minimizing runs on its own serial queue: AX calls can be slow for a napping
/// app, while the hot key itself must return instantly. Every press re-reads the
/// window list, so a press never depends on a remembered target that rapidly
/// changing focus could invalidate.
private final class MinimizeCascade {
    private let queue = DispatchQueue(label: "local.tgs.finderhotkey.minimize", qos: .userInteractive)
    private let lock = NSLock()
    private var generation: UInt64 = 0

    func request() {
        guard isTrusted() else {
            showPermissionAlertIfNeeded()
            return
        }
        lock.lock()
        let gen = generation
        lock.unlock()
        queue.async {
            guard self.isCurrent(gen) else { return }
            self.minimizeFrontWindow(generation: gen)
        }
    }

    func cancel() {
        lock.lock()
        generation &+= 1
        lock.unlock()
    }

    private func isCurrent(_ gen: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == gen
    }

    private func minimizeFrontWindow(generation: UInt64) {
        guard let candidate = cascadeCandidates(limit: 1).first else {
            focusScheduler.cancel()
            return
        }

        // The frame from the window server can lag a window that is still
        // animating, so retry the same window once before giving up. Never skip
        // to a window behind it: that would look like the wrong window vanished.
        for attempt in 0..<2 {
            if attempt > 0 { usleep(60_000) }
            // Cancelling (Show Desktop) must stop work that is already resolving
            // a window, not only the requests still waiting in the queue.
            guard isCurrent(generation) else { return }
            guard let match = resolveWindow(pid: candidate.pid, frame: candidate.frame) else { continue }
            guard isCurrent(generation) else { return }
            guard AXUIElementSetAttributeValue(match.window,
                                               kAXMinimizedAttribute as CFString,
                                               kCFBooleanTrue) == .success else { continue }
            minimizedWindowStore.record(pid: candidate.pid, frame: match.frame)
            focusScheduler.scheduleFrontWindowFocus()
            return
        }
        // Nothing was minimized, so do not pull another app forward: that would
        // look like the focus disappeared without the window being minimized.
        focusScheduler.cancel()
    }
}

private let minimizeCascade = MinimizeCascade()

private func minimizeFrontWindow() {
    minimizeCascade.request()
}

// MARK: - Show desktop toggle (Cmd + D)

// The window server runs its native Show Desktop action as the symbolic hot key
// with id 36. Firing that hot key lets the system move every window aside in one
// coordinated pass and put each back exactly where it was, so neither direction
// shows the per-window z-order flash that minimizing windows one by one caused.
private enum ShowDesktopHotKey {
    private typealias GetValueFn = @convention(c) (Int32,
                                                  UnsafeMutablePointer<UInt16>,
                                                  UnsafeMutablePointer<UInt16>,
                                                  UnsafeMutablePointer<UInt32>) -> Int32

    private static let getValue: GetValueFn? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let symbol = dlsym(handle, "CGSGetSymbolicHotKeyValue") else { return nil }
        return unsafeBitCast(symbol, to: GetValueFn.self)
    }()

    /// Key code and modifier flags currently bound to Show Desktop. A plain
    /// function key binding (the default F11) carries the function-key flag,
    /// which the window server requires to recognize the hot key.
    static var binding: (keyCode: CGKeyCode, flags: CGEventFlags) {
        if let getValue {
            var keyEquivalent: UInt16 = 0
            var keyCode: UInt16 = 0
            var modifiers: UInt32 = 0
            if getValue(36, &keyEquivalent, &keyCode, &modifiers) == 0,
               keyCode != 0, keyCode != 0xFFFF {
                return (CGKeyCode(keyCode), CGEventFlags(rawValue: UInt64(modifiers)))
            }
        }
        // Fallback: the system default binding, fn + F11.
        return (CGKeyCode(kVK_F11), .maskSecondaryFn)
    }
}

private final class DesktopToggle {
    private var lastAction = Date.distantPast

    func toggle() {
        guard isTrusted() else {
            showPermissionAlertIfNeeded()
            return
        }
        // Debounce key auto-repeat.
        guard Date().timeIntervalSince(lastAction) > 0.25 else { return }
        lastAction = Date()

        // Cmd+D takes over focus handling; stop any pending Cmd+Esc focus switch.
        minimizeCascade.cancel()
        focusScheduler.cancel()

        DispatchQueue.main.async {
            let binding = ShowDesktopHotKey.binding
            guard let down = CGEvent(keyboardEventSource: nil,
                                     virtualKey: binding.keyCode,
                                     keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil,
                                   virtualKey: binding.keyCode,
                                   keyDown: false) else { return }
            // The synthetic key down must carry the hot key's own flags (fn for
            // F11), not the Cmd the user is still holding for Cmd+D, or the
            // window server will not match it. Restore the live modifier state
            // on key up. Post at the session tap, where symbolic hot keys are
            // recognized.
            let heldFlags = up.flags
            down.flags = binding.flags
            up.flags = heldFlags
            down.post(tap: .cgSessionEventTap)
            up.post(tap: .cgSessionEventTap)
        }
    }
}

private let desktopToggle = DesktopToggle()
private let toastController = ToastController()

// MARK: - Hot keys

/// One physical press must produce one action. A second event can follow while
/// the key is still down (held-key repeat, key chatter, or a duplicate
/// delivery); those are swallowed. The gate re-arms on the Carbon release event
/// and, as a fallback, once a short poll sees the physical key up. The minimum
/// interval absorbs a bounce whose release is too brief for the poll to see,
/// while staying well below a human double tap.
private final class HotKeyReleaseGate {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "local.tgs.finderhotkey.keyrelease", qos: .userInteractive)
    private var isReady = true
    private var lastAccepted: UInt64 = 0
    private var generation: UInt64 = 0
    private var timer: DispatchSourceTimer?

    private let minimumInterval: UInt64 = 80_000_000
    private let pollInterval = DispatchTimeInterval.milliseconds(10)

    /// Returns true once per physical key press.
    func consume(keyCode: UInt32) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = DispatchTime.now().uptimeNanoseconds
        guard isReady, now &- lastAccepted >= minimumInterval else { return false }
        isReady = false
        lastAccepted = now
        generation &+= 1
        startPollingLocked(keyCode: keyCode, generation: generation)
        return true
    }

    /// Re-arms from the Carbon release event, which is authoritative.
    func rearm() {
        lock.lock()
        isReady = true
        generation &+= 1
        timer?.cancel()
        timer = nil
        lock.unlock()
    }

    private func startPollingLocked(keyCode: UInt32, generation: UInt64) {
        timer?.cancel()
        let poll = DispatchSource.makeTimerSource(queue: queue)
        poll.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        poll.setEventHandler { [weak self] in
            guard let self = self else { return }
            guard !CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode)) else { return }
            self.lock.lock()
            if self.generation == generation {
                self.isReady = true
                self.timer?.cancel()
                self.timer = nil
            }
            self.lock.unlock()
        }
        timer = poll
        poll.resume()
    }
}

private let openFinderKeyGate = HotKeyReleaseGate()
private let minimizeKeyGate = HotKeyReleaseGate()
private let desktopToggleKeyGate = HotKeyReleaseGate()

private func repeatGate(for id: HotKeyID) -> HotKeyReleaseGate {
    switch id {
    case .openFinder: return openFinderKeyGate
    case .minimizeFrontWindow: return minimizeKeyGate
    case .toggleDesktop: return desktopToggleKeyGate
    }
}

private func hotKeyHandler(_ callRef: EventHandlerCallRef?,
                           _ event: EventRef?,
                           _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event = event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &hotKeyID)
    guard status == noErr, let id = HotKeyID(rawValue: hotKeyID.id) else {
        return OSStatus(eventNotHandledErr)
    }
    // The release event re-arms the gate; only a fresh press runs the action.
    if GetEventKind(event) == UInt32(kEventHotKeyReleased) {
        repeatGate(for: id).rearm()
        return noErr
    }
    // A held key keeps producing events; only the first one counts.
    guard repeatGate(for: id).consume(keyCode: HotKeySettings.keyCode(id)) else {
        return noErr
    }
    showHotKeyToast(id)
    switch id {
    case .openFinder:
        openFinder()
    case .minimizeFrontWindow:
        minimizeFrontWindow()
    case .toggleDesktop:
        desktopToggle.toggle()
    }
    return noErr
}

private func showHotKeyToast(_ id: HotKeyID) {
    guard AppSettings.showsToast else { return }
    DispatchQueue.main.async {
        toastController.show(id)
    }
}

private func installHotKeyHandler() {
    var eventTypes = [
        EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                      eventKind: UInt32(kEventHotKeyPressed)),
        EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                      eventKind: UInt32(kEventHotKeyReleased)),
    ]
    InstallEventHandler(GetApplicationEventTarget(),
                        hotKeyHandler,
                        eventTypes.count,
                        &eventTypes,
                        nil,
                        nil)
}

private func unregisterHotKeys() {
    for ref in hotKeyRefs {
        UnregisterEventHotKey(ref)
    }
    hotKeyRefs.removeAll()
}

/// Registers only the enabled features with their configured combinations.
/// Returns the features the system refused, normally because another app owns
/// the same combination.
@discardableResult
private func applyHotKeys() -> [HotKeyID] {
    unregisterHotKeys()
    var failures: [HotKeyID] = []
    for id in HotKeyID.allCases where HotKeySettings.isEnabled(id) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: id.rawValue)
        let status = RegisterEventHotKey(HotKeySettings.keyCode(id),
                                         HotKeySettings.modifiers(id),
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        if status == noErr, let ref = ref {
            hotKeyRefs.append(ref)
        } else {
            failures.append(id)
        }
    }
    return failures
}

// MARK: - Settings UI

private final class ShortcutRecorderView: NSView {
    var keyCode: UInt32 {
        didSet { needsDisplay = true }
    }
    var modifiers: UInt32 {
        didSet { needsDisplay = true }
    }
    var isFunctionEnabled = true {
        didSet { needsDisplay = true }
    }
    var onBeginRecording: (() -> Void)?
    var onCommit: ((UInt32, UInt32) -> Bool)?
    var onCancel: (() -> Void)?

    private(set) var isRecording = false
    private var keyMonitor: Any?

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        removeKeyMonitor()
    }

    override var acceptsFirstResponder: Bool { isFunctionEnabled }
    override var canBecomeKeyView: Bool { isFunctionEnabled }

    override func resetCursorRects() {
        if isFunctionEnabled {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isFunctionEnabled else { return }
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
        beginRecording()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        // Normally the local monitor consumes keys first; this is a fallback.
        _ = record(event)
    }

    /// Starts capturing keys. A local monitor is used because AppKit turns some
    /// combinations such as ⌘esc and ⌃esc into `cancelOperation:` instead of
    /// delivering them to `keyDown`, which made them impossible to record.
    private func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        needsDisplay = true
        installKeyMonitor()
        onBeginRecording?()
    }

    /// Stops recording without committing and without reporting a cancel.
    func endRecording() {
        guard isRecording else { return }
        stopRecording()
        if window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
    }

    private func stopRecording() {
        removeKeyMonitor()
        isRecording = false
        needsDisplay = true
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self, self.isRecording else { return event }
            // Ignore keys aimed at another window (for example an alert sheet).
            if let eventWindow = event.window, eventWindow !== self.window {
                return event
            }
            return self.record(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    /// Handles one key press. Returns true when the event was consumed.
    private func record(_ event: NSEvent) -> Bool {
        guard isRecording else { return false }
        if event.isARepeat { return true }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let active = flags.intersection([.command, .option, .control, .shift])
        let pressedKeyCode = UInt32(event.keyCode)

        // Escape on its own cancels recording.
        if pressedKeyCode == UInt32(kVK_Escape) && active.isEmpty {
            finish(commit: false)
            return true
        }

        // Function keys work on their own; other keys need ⌘, ⌥ or ⌃.
        let isFunctionKey = functionKeyNames[Int(pressedKeyCode)] != nil
        guard active.contains(.command) || active.contains(.option) || active.contains(.control) || isFunctionKey else {
            NSSound.beep()
            return true
        }

        var carbonModifiers: UInt32 = 0
        if active.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if active.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if active.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        if active.contains(.command) { carbonModifiers |= UInt32(cmdKey) }

        guard onCommit?(pressedKeyCode, carbonModifiers) ?? false else { return true }
        self.keyCode = pressedKeyCode
        self.modifiers = carbonModifiers
        finish(commit: true)
        return true
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            stopRecording()
            onCancel?()
        }
        return true
    }

    private func finish(commit: Bool) {
        endRecording()
        if !commit {
            onCancel?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.75, dy: 0.75)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)

        let fillColor: NSColor
        let strokeColor: NSColor
        if isRecording {
            fillColor = NSColor.controlAccentColor.withAlphaComponent(0.16)
            strokeColor = NSColor.controlAccentColor
        } else if isFunctionEnabled {
            fillColor = NSColor.textBackgroundColor
            strokeColor = NSColor.separatorColor
        } else {
            fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6)
            strokeColor = NSColor.separatorColor.withAlphaComponent(0.5)
        }
        fillColor.setFill()
        path.fill()
        strokeColor.setStroke()
        path.lineWidth = isRecording ? 1.5 : 1
        path.stroke()

        let text: String
        let color: NSColor
        if !isFunctionEnabled {
            text = "未启用"
            color = NSColor.tertiaryLabelColor
        } else if isRecording {
            text = "按下快捷键…"
            color = NSColor.controlAccentColor
        } else {
            text = shortcutDescription(keyCode: keyCode, modifiers: modifiers)
            color = NSColor.labelColor
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: color,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let point = NSPoint(x: (bounds.width - size.width) / 2,
                            y: (bounds.height - size.height) / 2)
        (text as NSString).draw(at: point, withAttributes: attributes)
    }
}

private final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    private var recorders: [HotKeyID: ShortcutRecorderView] = [:]
    private var checkboxes: [HotKeyID: NSButton] = [:]
    private var finderTargetLabel: NSTextField?
    private var toastHoldField: NSTextField?
    private var toastFadeField: NSTextField?
    private var toastCheckbox: NSButton?
    private var toastBackgroundWell: NSColorWell?
    private var toastTextWell: NSColorWell?
    private var statusIconCheckbox: NSButton?
    private var unminimizeCheckbox: NSButton?
    private var saveButton: NSButton?
    private var pendingFinderPath: String? = AppSettings.finderPath
    private var hasUnsavedChanges = false {
        didSet { saveButton?.isEnabled = hasUnsavedChanges }
    }
    weak var statusBarController: StatusBarController?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 500),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "FinderHotKey 设置"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        buildContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Closing without saving discards staged changes; global hot keys that were
    /// unregistered for recording must be registered again.
    func windowWillClose(_ notification: Notification) {
        NSColorPanel.shared.close()
        reloadFromSaved()
    }

    func show() {
        guard let window = window else { return }
        // Reopening after a close starts from the saved values; bringing an
        // already visible window forward must keep staged edits.
        if !window.isVisible {
            reloadFromSaved()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func controlTextDidChange(_ obj: Notification) {
        markChanged()
    }

    private static let contentWidth: CGFloat = 560
    private static let contentInset: CGFloat = 22

    private func buildContent() {
        guard let content = window?.contentView else { return }

        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 18

        var shortcutRows: [NSView] = [makeHeaderRow()]
        for id in HotKeyID.allCases {
            shortcutRows.append(makeRow(for: id))
            if id == .openFinder {
                shortcutRows.append(makeFinderTargetRow())
            }
        }
        let shortcutsSection = makeSection("快捷键", rows: shortcutRows)

        let unminimizeCheckbox = NSButton(checkboxWithTitle: "切到窗口已全部最小化的应用时自动还原",
                                          target: self,
                                          action: #selector(toggleUnminimizeOnActivate(_:)))
        unminimizeCheckbox.state = AppSettings.unminimizeActivatedApp ? .on : .off
        unminimizeCheckbox.toolTip = "切换到所有窗口都已最小化的应用时，自动还原它的最小化窗口；“访达”不处理，避免点击桌面时误触发"
        self.unminimizeCheckbox = unminimizeCheckbox
        let behaviorSection = makeSection("窗口行为", rows: [unminimizeCheckbox])

        let showToastCheckbox = NSButton(checkboxWithTitle: "显示触发提示",
                                         target: self,
                                         action: #selector(toggleToast(_:)))
        showToastCheckbox.state = AppSettings.showsToast ? .on : .off
        showToastCheckbox.toolTip = "快捷键触发时在屏幕中央短暂显示该快捷键"
        toastCheckbox = showToastCheckbox
        let toastSection = makeSection("触发提示", rows: [
            showToastCheckbox,
            makeToastRow(),
            makeToastColorRow(),
        ])

        let showIconCheckbox = NSButton(checkboxWithTitle: "在菜单栏显示图标",
                                        target: self,
                                        action: #selector(toggleStatusBarIcon(_:)))
        showIconCheckbox.state = AppSettings.showsStatusBarIcon ? .on : .off
        showIconCheckbox.toolTip = "关闭后应用仍在后台运行；再次打开 FinderHotKey 即可显示设置窗口"
        statusIconCheckbox = showIconCheckbox
        let menuSection = makeSection("菜单栏", rows: [showIconCheckbox])

        for section in [shortcutsSection, behaviorSection, toastSection, menuSection] {
            root.addArrangedSubview(section)
            section.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }

        let divider = NSBox()
        divider.boxType = .separator
        root.addArrangedSubview(divider)
        divider.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        root.setCustomSpacing(12, after: divider)

        let note = NSTextField(wrappingLabelWithString:
            "点击快捷键后按下新的组合键，按 Esc 取消。所有修改需点击“保存”才会生效并关闭窗口；直接关闭窗口会放弃修改。")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = Self.contentWidth - Self.contentInset * 2
        root.addArrangedSubview(note)
        note.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        root.setCustomSpacing(14, after: note)

        let resetButton = NSButton(title: "恢复默认", target: self, action: #selector(resetDefaults))
        resetButton.bezelStyle = .rounded
        let quitButton = NSButton(title: "退出", target: self, action: #selector(quitApp))
        quitButton.bezelStyle = .rounded
        quitButton.toolTip = "退出后快捷键将停止，直到重新打开应用或下次登录"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let saveButton = NSButton(title: "保存", target: self, action: #selector(saveAndClose))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.isEnabled = false
        saveButton.toolTip = "保存全部修改并生效"
        self.saveButton = saveButton
        let buttons = NSStackView(views: [quitButton, spacer, resetButton, saveButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        root.addArrangedSubview(buttons)
        buttons.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Self.contentInset),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Self.contentInset),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
        ])

        content.layoutSubtreeIfNeeded()
        let height = ceil(root.fittingSize.height) + 40
        window?.setContentSize(NSSize(width: Self.contentWidth, height: height))
        window?.center()
        updateToastControlsEnabled()
    }

    private func makeSection(_ title: String, rows: [NSView]) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor

        let body = NSStackView()
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 10
        for row in rows {
            body.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        }

        let section = NSStackView(views: [titleLabel, body])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 7
        body.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        return section
    }

    private func makeHeaderRow() -> NSStackView {
        let feature = headerLabel("功能")
        feature.widthAnchor.constraint(equalToConstant: 170).isActive = true
        let shortcut = headerLabel("快捷键")
        shortcut.widthAnchor.constraint(equalToConstant: 170).isActive = true
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let enabled = headerLabel("启用")
        enabled.alignment = .right
        enabled.widthAnchor.constraint(equalToConstant: 30).isActive = true

        let row = NSStackView(views: [feature, shortcut, spacer, enabled])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func headerLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeRow(for id: HotKeyID) -> NSStackView {
        let name = NSTextField(labelWithString: id.title)
        name.font = .systemFont(ofSize: 13)
        name.widthAnchor.constraint(equalToConstant: 170).isActive = true

        let recorder = ShortcutRecorderView(keyCode: HotKeySettings.keyCode(id),
                                            modifiers: HotKeySettings.modifiers(id))
        recorder.isFunctionEnabled = HotKeySettings.isEnabled(id)
        recorder.toolTip = "点击后按下新的快捷键"
        recorder.onBeginRecording = {
            // Registered global hot keys swallow key events; release them so the
            // recorder can receive the combination being typed.
            unregisterHotKeys()
        }
        recorder.onCommit = { [weak self] keyCode, modifiers in
            self?.commitShortcut(for: id, keyCode: keyCode, modifiers: modifiers) ?? false
        }
        recorder.onCancel = {
            // Recording unregisters the hot keys; restore the saved ones.
            _ = applyHotKeys()
        }
        recorder.widthAnchor.constraint(equalToConstant: 170).isActive = true
        recorder.heightAnchor.constraint(equalToConstant: 26).isActive = true

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleEnabled(_:)))
        checkbox.tag = Int(id.rawValue)
        checkbox.state = HotKeySettings.isEnabled(id) ? .on : .off
        checkbox.toolTip = "启用或停用“\(id.title)”"
        checkbox.setAccessibilityLabel("启用\(id.title)")

        recorders[id] = recorder
        checkboxes[id] = checkbox

        let row = NSStackView(views: [name, recorder, spacer, checkbox])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    /// Folder picker row shown under “打开访达”.
    private func makeFinderTargetRow() -> NSStackView {
        let caption = NSTextField(labelWithString: "打开位置")
        caption.font = .systemFont(ofSize: 11)
        caption.textColor = .secondaryLabelColor
        caption.widthAnchor.constraint(equalToConstant: 170).isActive = true

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        finderTargetLabel = label
        updateFinderTargetLabel()

        let chooseButton = NSButton(title: "选择…", target: self, action: #selector(chooseFinderTarget))
        chooseButton.bezelStyle = .rounded
        chooseButton.controlSize = .small
        chooseButton.toolTip = "选择“打开访达”要打开的文件夹"

        let row = NSStackView(views: [caption, label, trailingSpacer(), chooseButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    /// Hold/fade timing for the trigger hint, in milliseconds.
    private func makeToastRow() -> NSStackView {
        let holdField = makeToastField(milliseconds: AppSettings.toastHoldMilliseconds)
        holdField.toolTip = "提示保持完全显示的时间；这段时间结束后开始淡出（0–5000 毫秒）"
        toastHoldField = holdField
        let fadeField = makeToastField(milliseconds: AppSettings.toastFadeMilliseconds)
        fadeField.toolTip = "从开始淡出到完全消失所用的时间（0–5000 毫秒）"
        toastFadeField = fadeField

        let row = NSStackView(views: [
            indentSpacer(),
            settingLabel("停留"),
            holdField,
            unitLabel("毫秒"),
            columnGap(),
            settingLabel("淡出"),
            fadeField,
            unitLabel("毫秒"),
            trailingSpacer(),
        ])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        return row
    }

    private func unitLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func settingLabel(_ text: String) -> NSTextField {
        let label = unitLabel(text)
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 30).isActive = true
        return label
    }

    private func indentSpacer() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 19).isActive = true
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }

    private func columnGap() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 24).isActive = true
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }

    /// Aligns the second color well with the fade field above it.
    private func colorColumnGap() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 62).isActive = true
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }

    private func trailingSpacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }

    /// Background and text colors for the trigger hint, edited with the system
    /// color picker.
    private func makeToastColorRow() -> NSStackView {
        let backgroundWell = makeColorWell(color: AppSettings.toastBackgroundColor,
                                           action: #selector(toastBackgroundColorChanged(_:)),
                                           toolTip: "触发提示的背景颜色，支持透明度")
        toastBackgroundWell = backgroundWell
        let textWell = makeColorWell(color: AppSettings.toastTextColor,
                                     action: #selector(toastTextColorChanged(_:)),
                                     toolTip: "触发提示的文字和快捷键颜色，支持透明度")
        toastTextWell = textWell

        let row = NSStackView(views: [
            indentSpacer(),
            settingLabel("背景"),
            backgroundWell,
            colorColumnGap(),
            settingLabel("文字"),
            textWell,
            trailingSpacer(),
        ])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        return row
    }

    private func makeColorWell(color: NSColor, action: Selector, toolTip: String) -> NSColorWell {
        let well = NSColorWell()
        well.color = color
        well.target = self
        well.action = action
        well.isContinuous = true
        if #available(macOS 14.0, *) {
            well.supportsAlpha = true
        }
        NSColorPanel.shared.showsAlpha = true
        well.toolTip = toolTip
        well.translatesAutoresizingMaskIntoConstraints = false
        well.widthAnchor.constraint(equalToConstant: 44).isActive = true
        well.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return well
    }

    private func makeToastField(milliseconds: Int) -> NSTextField {
        let field = NSTextField(string: "\(milliseconds)")
        field.font = .systemFont(ofSize: 12)
        field.alignment = .right
        field.widthAnchor.constraint(equalToConstant: 52).isActive = true
        field.delegate = self

        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        formatter.minimum = 0
        formatter.maximum = 5000
        field.formatter = formatter
        return field
    }

    @objc private func toggleToast(_ sender: NSButton) {
        updateToastControlsEnabled()
        markChanged()
    }

    @objc private func toastBackgroundColorChanged(_ sender: NSColorWell) {
        markChanged()
    }

    @objc private func toastTextColorChanged(_ sender: NSColorWell) {
        markChanged()
    }

    private func updateToastControlsEnabled() {
        let enabled = toastCheckbox?.state == .on
        toastHoldField?.isEnabled = enabled
        toastFadeField?.isEnabled = enabled
        toastBackgroundWell?.isEnabled = enabled
        toastTextWell?.isEnabled = enabled
    }

    private func committedToastMilliseconds(from field: NSTextField?, stored: Int) -> Int {
        guard let field = field else { return stored }
        // The text may still live in the field editor if editing did not end.
        let text = (field.currentEditor()?.string ?? field.stringValue)
            .trimmingCharacters(in: .whitespaces)
        guard let value = Int(text) else {
            field.integerValue = stored
            return stored
        }
        let clamped = min(5000, max(0, value))
        if clamped != value {
            field.integerValue = clamped
        }
        return clamped
    }

    @objc private func chooseFinderTarget() {
        if recorders.values.contains(where: { $0.isRecording }) {
            stopRecordingAndReapplyHotKeys()
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "选择"
        panel.message = "选择“打开访达”快捷键要打开的文件夹"
        panel.directoryURL = URL(fileURLWithPath: pendingFinderPath ?? NSHomeDirectory())

        if let window = window, window.isVisible {
            panel.beginSheetModal(for: window) { [weak self] response in
                guard response == .OK, let url = panel.url else { return }
                self?.stageFinderPath(url.path)
            }
        } else if panel.runModal() == .OK, let url = panel.url {
            stageFinderPath(url.path)
        }
    }

    private func stageFinderPath(_ path: String) {
        pendingFinderPath = path
        updateFinderTargetLabel()
        markChanged()
    }

    private func updateFinderTargetLabel() {
        let path = pendingFinderPath ?? NSHomeDirectory()
        let abbreviated = (path as NSString).abbreviatingWithTildeInPath
        finderTargetLabel?.stringValue = pendingFinderPath == nil ? "主目录（\(abbreviated)）" : abbreviated
        finderTargetLabel?.toolTip = path
    }

    @objc private func toggleEnabled(_ sender: NSButton) {
        guard let id = HotKeyID(rawValue: UInt32(sender.tag)) else { return }
        // Leave recording mode before the enabled state changes.
        for recorder in recorders.values {
            recorder.endRecording()
        }
        recorders[id]?.isFunctionEnabled = sender.state == .on
        // endRecording does not restore the global hot keys by itself.
        _ = applyHotKeys()
        markChanged()
    }

    private func commitShortcut(for id: HotKeyID, keyCode: UInt32, modifiers: UInt32) -> Bool {
        if let conflict = HotKeyID.allCases.first(where: { other in
            guard other != id, let recorder = recorders[other] else { return false }
            return recorder.keyCode == keyCode && recorder.modifiers == modifiers
        }) {
            let alert = NSAlert()
            alert.messageText = "快捷键冲突"
            var detail = "“\(conflict.title)”已经使用了 \(shortcutDescription(keyCode: keyCode, modifiers: modifiers))。"
            if checkboxes[conflict]?.state != .on {
                detail += "该功能当前未启用，启用后会产生冲突。"
            }
            alert.informativeText = detail + "请换一个组合键。"
            show(alert)
            return false
        }
        // Recording unregisters the hot keys; keep the saved ones working until
        // the user clicks 保存.
        _ = applyHotKeys()
        markChanged()
        return true
    }

    func reportRegistrationFailures(_ failures: [HotKeyID]) {
        guard !failures.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "部分快捷键未能注册"
        alert.informativeText = "以下快捷键可能已被其他应用占用：\(failures.map(\.title).joined(separator: "、"))。请换一个组合键，或取消勾选该功能。"
        show(alert)
    }

    private func show(_ alert: NSAlert) {
        if let window = window, window.isVisible {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    @objc private func resetDefaults() {
        // Stage the defaults; they are applied only after clicking 保存.
        for id in HotKeyID.allCases {
            recorders[id]?.endRecording()
            recorders[id]?.isFunctionEnabled = true
            recorders[id]?.keyCode = id.defaultKeyCode
            recorders[id]?.modifiers = id.defaultModifiers
            checkboxes[id]?.state = .on
        }
        window?.makeFirstResponder(nil)
        _ = applyHotKeys()
        toastHoldField?.integerValue = AppSettings.defaultToastHoldMilliseconds
        toastFadeField?.integerValue = AppSettings.defaultToastFadeMilliseconds
        toastCheckbox?.state = .on
        toastBackgroundWell?.color = AppSettings.defaultToastBackgroundColor
        toastTextWell?.color = AppSettings.defaultToastTextColor
        unminimizeCheckbox?.state = .off
        updateToastControlsEnabled()
        markChanged()
    }

    @objc private func saveAndClose() {
        guard hasUnsavedChanges else { return }
        // Commit the field editor first so a freshly typed timing counts.
        window?.makeFirstResponder(nil)
        for recorder in recorders.values {
            recorder.endRecording()
        }

        let hold = committedToastMilliseconds(from: toastHoldField, stored: AppSettings.toastHoldMilliseconds)
        let fade = committedToastMilliseconds(from: toastFadeField, stored: AppSettings.toastFadeMilliseconds)

        if let conflict = stagedShortcutConflict() {
            let alert = NSAlert()
            alert.messageText = "快捷键冲突"
            alert.informativeText = "“\(conflict.first.title)”和“\(conflict.second.title)”都使用了 "
                + "\(shortcutDescription(keyCode: conflict.keyCode, modifiers: conflict.modifiers))。"
                + "请先修改其中一个，再点击保存。"
            show(alert)
            return
        }

        for id in HotKeyID.allCases {
            HotKeySettings.setEnabled(checkboxes[id]?.state == .on, for: id)
            if let recorder = recorders[id] {
                HotKeySettings.setShortcut(keyCode: recorder.keyCode,
                                           modifiers: recorder.modifiers,
                                           for: id)
            }
        }
        AppSettings.setShowsToast(toastCheckbox?.state == .on)
        AppSettings.setToastHoldMilliseconds(hold)
        AppSettings.setToastFadeMilliseconds(fade)
        if let color = toastBackgroundWell?.color {
            AppSettings.setToastBackgroundColor(color)
        }
        if let color = toastTextWell?.color {
            AppSettings.setToastTextColor(color)
        }
        let showsIcon = statusIconCheckbox.map { $0.state == .on } ?? AppSettings.showsStatusBarIcon
        AppSettings.setShowsStatusBarIcon(showsIcon)
        AppSettings.setUnminimizeActivatedApp(unminimizeCheckbox?.state == .on)
        if let path = pendingFinderPath {
            AppSettings.setFinderPath(path)
        }

        statusBarController?.setVisible(showsIcon)
        toastController.refreshAppearance()
        let failures = applyHotKeys()
        reloadFromSaved()
        window?.orderOut(nil)
        reportRegistrationFailures(failures)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func toggleStatusBarIcon(_ sender: NSButton) {
        markChanged()
    }

    @objc private func toggleUnminimizeOnActivate(_ sender: NSButton) {
        markChanged()
    }

    private func markChanged() {
        hasUnsavedChanges = true
    }

    private func stagedShortcutConflict() -> (first: HotKeyID, second: HotKeyID, keyCode: UInt32, modifiers: UInt32)? {
        var seen: [String: HotKeyID] = [:]
        for id in HotKeyID.allCases where checkboxes[id]?.state == .on {
            guard let recorder = recorders[id] else { continue }
            let key = "\(recorder.keyCode)-\(recorder.modifiers)"
            if let first = seen[key] {
                return (first, id, recorder.keyCode, recorder.modifiers)
            }
            seen[key] = id
        }
        return nil
    }

    /// Restores every control from the persisted settings and forgets staged
    /// changes. Global hot keys stop working while a shortcut is being recorded,
    /// so re-register them if that was the case.
    private func reloadFromSaved() {
        let wasRecording = recorders.values.contains { $0.isRecording }
        for id in HotKeyID.allCases {
            recorders[id]?.endRecording()
            recorders[id]?.isFunctionEnabled = HotKeySettings.isEnabled(id)
            recorders[id]?.keyCode = HotKeySettings.keyCode(id)
            recorders[id]?.modifiers = HotKeySettings.modifiers(id)
            checkboxes[id]?.state = HotKeySettings.isEnabled(id) ? .on : .off
        }
        pendingFinderPath = AppSettings.finderPath
        updateFinderTargetLabel()
        toastHoldField?.integerValue = AppSettings.toastHoldMilliseconds
        toastFadeField?.integerValue = AppSettings.toastFadeMilliseconds
        toastCheckbox?.state = AppSettings.showsToast ? .on : .off
        toastBackgroundWell?.color = AppSettings.toastBackgroundColor
        toastTextWell?.color = AppSettings.toastTextColor
        statusIconCheckbox?.state = AppSettings.showsStatusBarIcon ? .on : .off
        unminimizeCheckbox?.state = AppSettings.unminimizeActivatedApp ? .on : .off
        updateToastControlsEnabled()
        hasUnsavedChanges = false
        if wasRecording {
            _ = applyHotKeys()
        }
    }

    private func stopRecordingAndReapplyHotKeys() {
        for id in HotKeyID.allCases {
            recorders[id]?.endRecording()
        }
        _ = applyHotKeys()
    }
}

private final class StatusBarController: NSObject {
    private let settingsController: SettingsWindowController
    private var statusItem: NSStatusItem?

    init(settingsController: SettingsWindowController) {
        self.settingsController = settingsController
        super.init()
        setVisible(AppSettings.showsStatusBarIcon)
    }

    /// Shows or removes the menu bar icon immediately.
    func setVisible(_ visible: Bool) {
        if visible {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = item.button {
                if let image = NSImage(systemSymbolName: "command", accessibilityDescription: "FinderHotKey") {
                    image.isTemplate = true
                    button.image = image
                } else {
                    button.title = "⌘"
                }
                button.target = self
                button.action = #selector(handleClick(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                button.toolTip = "FinderHotKey：点击打开设置，右键查看更多"
            }
            statusItem = item
        } else {
            if let statusItem = statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
            statusItem = nil
        }
    }

    @objc private func handleClick(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            settingsController.show()
        }
    }

    private func showMenu() {
        guard let statusItem = statusItem else { return }
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let finderItem = NSMenuItem(title: "打开访达", action: #selector(openFinderFromMenu), keyEquivalent: "")
        finderItem.target = self
        menu.addItem(finderItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 FinderHotKey", action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openSettings() { settingsController.show() }
    @objc private func openFinderFromMenu() { openFinder() }
    @objc private func quit() { NSApp.terminate(nil) }
}

/// Small centered overlay that confirms a hot key fired. It never receives
/// mouse events and hides itself after the configured hold and fade times.
private final class ToastController {
    private let panel: NSPanel
    private let content: ToastContentView
    private var hideWorkItem: DispatchWorkItem?
    private var fadeGeneration = 0

    init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 156, height: 120),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // A window shadow around transparent content shows up as a light rim.
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        self.panel = panel

        let content = ToastContentView()
        content.autoresizingMask = [.width, .height]
        panel.contentView = content
        self.content = content
    }

    func show(_ id: HotKeyID) {
        content.update(keyCode: HotKeySettings.keyCode(id),
                       modifiers: HotKeySettings.modifiers(id),
                       background: AppSettings.toastBackgroundColor,
                       text: AppSettings.toastTextColor)
        let size = content.preferredSize
        panel.setContentSize(size)

        // Center on the screen the user is working on (the one with the key
        // window); never follows the mouse, matching system-default behavior.
        if let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: (visible.midX - size.width / 2).rounded(),
                                         y: (visible.midY - size.height / 2).rounded()))
        }

        fadeGeneration += 1
        let generation = fadeGeneration
        hideWorkItem?.cancel()
        panel.contentView?.layer?.removeAllAnimations()
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        let hold = AppSettings.toastHoldMilliseconds
        let fade = AppSettings.toastFadeMilliseconds
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard fade > 0 else {
                self.panel.orderOut(nil)
                return
            }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = Double(fade) / 1000
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self = self, self.fadeGeneration == generation else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            })
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(hold) / 1000, execute: work)
    }

    /// Applies newly chosen colors to a hint that is currently on screen.
    func refreshAppearance() {
        guard panel.isVisible else { return }
        content.applyColors(background: AppSettings.toastBackgroundColor,
                            text: AppSettings.toastTextColor)
    }
}

/// WeChat-style card showing only the shortcut that fired: solid dark gray,
/// large white type, generous corner radius. It draws its own background so the
/// panel has no frame or margin around it.
private final class ToastContentView: NSView {
    private static let shortcutFont = NSFont.systemFont(ofSize: 32, weight: .medium)
    private static let cornerRadius: CGFloat = 10
    private static let minimumWidth: CGFloat = 132
    private static let height: CGFloat = 120
    private static let horizontalPadding: CGFloat = 28

    private let shortcutLabel = NSTextField(labelWithString: "")
    private var shortcut = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        layer?.masksToBounds = true

        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        shortcutLabel.alignment = .center
        shortcutLabel.maximumNumberOfLines = 1
        addSubview(shortcutLabel)

        NSLayoutConstraint.activate([
            shortcutLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            shortcutLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            shortcutLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor,
                                                   constant: Self.horizontalPadding),
            shortcutLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor,
                                                    constant: -Self.horizontalPadding),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(keyCode: UInt32,
                modifiers: UInt32,
                background: NSColor,
                text: NSColor) {
        shortcut = shortcutHUDText(keyCode: keyCode, modifiers: modifiers)
        applyColors(background: background, text: text)
    }

    func applyColors(background: NSColor, text: NSColor) {
        layer?.backgroundColor = background.cgColor
        shortcutLabel.attributedStringValue = NSAttributedString(
            string: shortcut,
            attributes: [
                .font: Self.shortcutFont,
                .foregroundColor: text,
            ]
        )
    }

    var preferredSize: NSSize {
        // Measure the text itself: the label may currently be squeezed by the
        // panel's previous, narrower size.
        let textSize = shortcutLabel.attributedStringValue.size()
        return NSSize(width: max(Self.minimumWidth,
                                 ceil(textSize.width) + Self.horizontalPadding * 2),
                      height: Self.height)
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    var settingsController: SettingsWindowController?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsController?.show()
        return true
    }
}

// MARK: - Main

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

/// The installed app and a copy in dist/ share a bundle identifier, register
/// the same global hot keys and would both act on every press. Keep a single
/// instance; during an upgrade the previous copy may still be exiting, so wait
/// briefly before stepping aside.
private let otherInstances: () -> [NSRunningApplication] = {
    let bundleID = Bundle.main.bundleIdentifier ?? "local.tgs.finderhotkey"
    return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .filter { $0.processIdentifier != getpid() }
}
var waitAttempts = 0
while !otherInstances().isEmpty && waitAttempts < 15 {
    usleep(100_000)
    waitAttempts += 1
}
if !otherInstances().isEmpty {
    // A successful exit matters: the LaunchAgent only relaunches failures.
    exit(0)
}

private let settingsController = SettingsWindowController()
private let appDelegate = AppDelegate()
private let statusBarController = StatusBarController(settingsController: settingsController)

settingsController.statusBarController = statusBarController
appDelegate.settingsController = settingsController
app.delegate = appDelegate

installHotKeyHandler()

let environment = ProcessInfo.processInfo.environment
let launchedByAgent = environment["XPC_SERVICE_NAME"] == "local.tgs.finderhotkey"

private let failures = applyHotKeys()
// Ask for Accessibility once at launch; macOS only shows this when untrusted.
_ = isTrusted(prompt: true)
if !launchedByAgent {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        settingsController.show()
        settingsController.reportRegistrationFailures(failures)
    }
}

app.run()