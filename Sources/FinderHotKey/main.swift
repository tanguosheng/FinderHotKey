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
        case .openFinder: return "打开访达（主目录）"
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

    static func resetAll() {
        let defaults = UserDefaults.standard
        for id in HotKeyID.allCases {
            defaults.removeObject(forKey: key(id, "enabled"))
            defaults.removeObject(forKey: key(id, "keyCode"))
            defaults.removeObject(forKey: key(id, "modifiers"))
        }
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

// MARK: - Finder

private func openFinder() {
    NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()))
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

private struct OrderedWindow {
    let pid: pid_t
    let frame: CGRect
    let display: CGDirectDisplayID
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

/// Windows grouped by display: current display first (front to back),
/// then every other display in the order its frontmost window appears.
private func orderedWindows(allOnScreen: [OnScreenWindowInfo],
                            displays: [DisplayBounds],
                            currentDisplay: CGDirectDisplayID?) -> [OrderedWindow] {
    let annotated: [OrderedWindow] = allOnScreen.compactMap { info in
        guard let display = displayID(for: info.frame, in: displays) else { return nil }
        return OrderedWindow(pid: info.pid, frame: info.frame, display: display)
    }
    guard let current = currentDisplay else { return annotated }

    var result = annotated.filter { $0.display == current }
    var added: Set<CGDirectDisplayID> = [current]
    for window in annotated where !added.contains(window.display) {
        added.insert(window.display)
        result.append(contentsOf: annotated.filter { $0.display == window.display })
    }
    return result
}

/// Activates the application and focuses the window matching the given frame.
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

private struct PendingCascadeTarget {
    let window: OrderedWindow
    let expiresAt: Date
}

private var pendingCascadeTarget: PendingCascadeTarget?
private var lastMinimizedPID: pid_t?
private var lastMinimizedFrame: CGRect?
private var lastMinimizedAt = Date.distantPast

private func clearPendingCascadeTarget() {
    pendingCascadeTarget = nil
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

    /// Focuses the next window after a short quiet period. Rapid Cmd+Esc presses
    /// keep pushing this back, so intermediate apps never flash to the front.
    func schedule(pid: pid_t, frame: CGRect) {
        lock.lock()
        generation &+= 1
        let gen = generation
        pendingWork?.cancel()
        lock.unlock()

        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.isCurrent(gen) else { return }
            // Mark only when we actually start activating, so a canceled focus
            // never masks a real app switch.
            self.markExpectedActivation(pid)
            focusWindow(pid: pid, frame: frame) { !self.isCurrent(gen) }
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

    private func applicationDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        // Clicking the Finder desktop does not cancel the cascade.
        if app.bundleIdentifier == "com.apple.finder" { return }
        // This activation was requested by our own focus operation.
        if isExpectedActivation(app.processIdentifier) { return }

        // The user switched to another app: do not pull focus back later.
        cancel()
        clearPendingCascadeTarget()
    }
}

private let focusScheduler = FocusScheduler()

// MARK: - Minimize front window (Cmd + Esc)

private func resolveWindow(pid: pid_t, frame: CGRect) -> (window: AXUIElement, frame: CGRect)? {
    let appElement = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(appElement, 0.4)

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

private func minimizeFrontWindow() {
    guard isTrusted() else {
        showPermissionAlertIfNeeded()
        return
    }

    var currentPID: pid_t?
    var currentFrame: CGRect?
    var currentWindow: AXUIElement?

    if let front = NSWorkspace.shared.frontmostApplication {
        let appElement = AXUIElementCreateApplication(front.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.4)
        if let value = copyAttribute(appElement, kAXFocusedWindowAttribute as String),
           CFGetTypeID(value) == AXUIElementGetTypeID() {
            let focused = unsafeBitCast(value, to: AXUIElement.self)
            // After a press the app may still report the window we just
            // minimized as focused, so only accept a live window.
            if let frame = windowFrame(focused), !isMinimized(focused) {
                let justMinimized = Date().timeIntervalSince(lastMinimizedAt) < 1.0 &&
                    lastMinimizedPID == front.processIdentifier &&
                    lastMinimizedFrame.map { framesMatch(frame, $0) } == true
                if !justMinimized {
                    currentPID = front.processIdentifier
                    currentFrame = frame
                    currentWindow = focused
                }
            }
        }
    }

    // Rapid presses: focus has not landed on the next window yet, so continue
    // from the window that is about to be focused instead of stalling.
    if currentWindow == nil,
       let pending = pendingCascadeTarget,
       Date() < pending.expiresAt,
       let match = resolveWindow(pid: pending.window.pid, frame: pending.window.frame) {
        currentPID = pending.window.pid
        currentFrame = match.frame
        currentWindow = match.window
    }

    guard let pid = currentPID, let frame = currentFrame, let current = currentWindow else {
        clearPendingCascadeTarget()
        focusScheduler.cancel()
        return
    }

    let allOnScreen = onScreenWindows()
    let displays = activeDisplays()
    let currentDisplay = displayID(for: frame, in: displays)
    let sequence = orderedWindows(allOnScreen: allOnScreen, displays: displays, currentDisplay: currentDisplay)
    let currentIndex = sequence.firstIndex { $0.pid == pid && framesMatch($0.frame, frame) }

    guard AXUIElementSetAttributeValue(current, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success else {
        clearPendingCascadeTarget()
        focusScheduler.cancel()
        return
    }
    lastMinimizedPID = pid
    lastMinimizedFrame = frame
    lastMinimizedAt = Date()

    // Stay on this display until its stack is exhausted, then continue on the next display.
    var target: OrderedWindow?
    if let index = currentIndex {
        if index + 1 < sequence.count {
            target = sequence[index + 1]
        }
    } else {
        target = sequence.first { !($0.pid == pid && framesMatch($0.frame, frame)) }
    }

    if let next = target {
        pendingCascadeTarget = PendingCascadeTarget(window: next,
                                                    expiresAt: Date().addingTimeInterval(1.0))
        focusScheduler.schedule(pid: next.pid, frame: next.frame)
    } else {
        clearPendingCascadeTarget()
        focusScheduler.cancel()
    }
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
        clearPendingCascadeTarget()
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

// MARK: - Hot keys

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

private func installHotKeyHandler() {
    var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                  eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &eventType, nil, nil)
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
        guard !isRecording else { return }
        isRecording = true
        needsDisplay = true
        onBeginRecording?()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let active = flags.intersection([.command, .option, .control, .shift])
        let pressedKeyCode = UInt32(event.keyCode)

        // Escape on its own cancels recording.
        if pressedKeyCode == UInt32(kVK_Escape) && active.isEmpty {
            finish(commit: false)
            return
        }

        guard active.contains(.command) || active.contains(.option) || active.contains(.control) else {
            NSSound.beep()
            return
        }

        var carbonModifiers: UInt32 = 0
        if active.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if active.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if active.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        if active.contains(.command) { carbonModifiers |= UInt32(cmdKey) }

        guard onCommit?(pressedKeyCode, carbonModifiers) ?? false else { return }
        self.keyCode = pressedKeyCode
        self.modifiers = carbonModifiers
        finish(commit: true)
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            isRecording = false
            needsDisplay = true
            onCancel?()
        }
        return true
    }

    private func finish(commit: Bool) {
        isRecording = false
        needsDisplay = true
        if !commit {
            onCancel?()
        }
        window?.makeFirstResponder(nil)
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

private final class SettingsWindowController: NSWindowController {
    private var recorders: [HotKeyID: ShortcutRecorderView] = [:]
    private var checkboxes: [HotKeyID: NSButton] = [:]

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 264),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "FinderHotKey 设置"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        buildContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window = window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12

        let header = makeHeaderRow()
        stack.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        for id in HotKeyID.allCases {
            let row = makeRow(for: id)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let hint = NSTextField(wrappingLabelWithString:
            "点击快捷键后按下新的组合键即可修改，按 Esc 取消。取消勾选可停用对应功能。所有修改立即生效并自动保存。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = 500
        stack.addArrangedSubview(hint)
        hint.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let resetButton = NSButton(title: "恢复默认", target: self, action: #selector(resetDefaults))
        resetButton.bezelStyle = .rounded
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let doneButton = NSButton(title: "完成", target: self, action: #selector(closeWindow))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        let buttons = NSStackView(views: [resetButton, spacer, doneButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        stack.addArrangedSubview(buttons)
        buttons.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
        ])
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

    @objc private func toggleEnabled(_ sender: NSButton) {
        guard let id = HotKeyID(rawValue: UInt32(sender.tag)) else { return }
        let enabled = sender.state == .on
        HotKeySettings.setEnabled(enabled, for: id)
        recorders[id]?.isFunctionEnabled = enabled
        reportRegistrationFailures(applyHotKeys())
    }

    private func commitShortcut(for id: HotKeyID, keyCode: UInt32, modifiers: UInt32) -> Bool {
        if let conflict = HotKeyID.allCases.first(where: {
            $0 != id && HotKeySettings.keyCode($0) == keyCode && HotKeySettings.modifiers($0) == modifiers
        }) {
            let alert = NSAlert()
            alert.messageText = "快捷键冲突"
            var detail = "“\(conflict.title)”已经使用了 \(shortcutDescription(keyCode: keyCode, modifiers: modifiers))。"
            if !HotKeySettings.isEnabled(conflict) {
                detail += "该功能当前未启用，启用后会产生冲突。"
            }
            alert.informativeText = detail + "请换一个组合键。"
            show(alert)
            return false
        }
        HotKeySettings.setShortcut(keyCode: keyCode, modifiers: modifiers, for: id)
        reportRegistrationFailures(applyHotKeys())
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
        HotKeySettings.resetAll()
        for id in HotKeyID.allCases {
            recorders[id]?.isFunctionEnabled = true
            recorders[id]?.keyCode = id.defaultKeyCode
            recorders[id]?.modifiers = id.defaultModifiers
            checkboxes[id]?.state = .on
        }
        reportRegistrationFailures(applyHotKeys())
    }

    @objc private func closeWindow() {
        window?.orderOut(nil)
    }
}

private final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let settingsController: SettingsWindowController

    init(settingsController: SettingsWindowController) {
        self.settingsController = settingsController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "command", accessibilityDescription: "FinderHotKey") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "⌘"
            }
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "FinderHotKey：点击打开设置"
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

private let settingsController = SettingsWindowController()
private let appDelegate = AppDelegate()
private let statusBarController = StatusBarController(settingsController: settingsController)

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

_ = statusBarController

app.run()