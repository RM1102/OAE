import Foundation
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine

/// System-wide key-code constants for modifier-side distinction.
/// Values come from `/System/Library/Frameworks/Carbon.framework/Headers/Events.h`.
public enum PTTKey {
    public static let leftOption:  Int64 = 0x3A  // kVK_Option
    public static let rightOption: Int64 = 0x3D  // kVK_RightOption
    public static let leftShift:   Int64 = 0x38
    public static let rightShift:  Int64 = 0x3C
    public static let leftCommand: Int64 = 0x37
    public static let rightCommand:Int64 = 0x36
    public static let leftControl: Int64 = 0x3B
    public static let rightControl:Int64 = 0x3E
    public static let space:       Int64 = 0x31  // non-modifier; for Opt+Shift+Space
}

public enum HotkeyEvent: Equatable, Sendable {
    case pttStart          // right Option pressed
    case pttStop           // left Option pressed
    case postProcess       // Option+Shift+Space (remappable)
}

/// Installs a CGEventTap that distinguishes left vs right Option via keyCode
/// (`kVK_Option` = 0x3A, `kVK_RightOption` = 0x3D). Requires Accessibility
/// permission. Publishes a Combine `events` stream for any subscriber.
@MainActor
public final class HotkeyManager: ObservableObject {
    public static let shared = HotkeyManager()

    @Published public private(set) var isTapInstalled: Bool = false
    @Published public private(set) var trustGranted: Bool = false

    public let events = PassthroughSubject<HotkeyEvent, Never>()

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Modifier state so flagsChanged press/release is unambiguous.
    private var rightOptDown = false
    private var leftOptDown = false
    private var shiftDown = false

    private init() {}

    public func checkTrust(prompt: Bool) -> Bool {
        let opts: [String: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
        let trusted = AXIsProcessTrustedWithOptions(opts as CFDictionary)
        trustGranted = trusted
        return trusted
    }

    public func install() {
        guard tap == nil else { return }
        _ = checkTrust(prompt: false)

        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            // The tap can invoke this callback off the main queue; `HotkeyManager` is `@MainActor`.
            DispatchQueue.main.async {
                manager.handle(type: type, event: event)
            }
            return Unmanaged.passUnretained(event)
        }

        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: selfPtr
        ) else {
            isTapInstalled = false
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        self.tap = newTap
        self.runLoopSource = source
        self.isTapInstalled = true
    }

    public func uninstall() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil; runLoopSource = nil; isTapInstalled = false
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .flagsChanged:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags
            switch keyCode {
            case PTTKey.rightOption:
                let nowDown = flags.contains(.maskAlternate)
                if nowDown && !rightOptDown {
                    rightOptDown = true
                    DispatchQueue.main.async { self.events.send(.pttStart) }
                } else if !nowDown {
                    rightOptDown = false
                }
            case PTTKey.leftOption:
                let nowDown = flags.contains(.maskAlternate)
                if nowDown && !leftOptDown {
                    leftOptDown = true
                    DispatchQueue.main.async { self.events.send(.pttStop) }
                } else if !nowDown {
                    leftOptDown = false
                }
            case PTTKey.leftShift, PTTKey.rightShift:
                shiftDown = flags.contains(.maskShift)
            default:
                break
            }
        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags
            let hasOpt = flags.contains(.maskAlternate)
            let hasShift = flags.contains(.maskShift)
            let hasCmd = flags.contains(.maskCommand)
            if keyCode == PTTKey.space && hasOpt && hasShift && !hasCmd {
                DispatchQueue.main.async { self.events.send(.postProcess) }
            }
        default:
            break
        }
    }

    /// Simulates Cmd+V into the currently focused app. Used for auto-paste on PTT finalize.
    public static func simulatePaste() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        let vUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags   = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
    }
}
