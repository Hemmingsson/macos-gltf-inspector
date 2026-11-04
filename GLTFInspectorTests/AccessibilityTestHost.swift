import AppKit
import SwiftUI
import Testing

/// Real component accessibility, hosted in a test-owned off-screen window (never key/front).
@MainActor
final class AccessibilityTestHost<Content: View> {
    let window: NSWindow
    let view: NSHostingView<Content>

    init(_ content: Content) async {
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXManualAccessibility"))
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        view = NSHostingView(rootView: content)
        // On-screen so `accessibilityFrame` is non-empty; never made key or ordered front.
        window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 900, height: 900),
                          styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: 900, height: 900)
        window.orderFrontRegardless()
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        view.layoutSubtreeIfNeeded()
    }

    func close() { window.contentView = nil; window.close() }

    private func attribute(_ name: String, of element: NSObject) -> Any? {
        let selector = NSSelectorFromString(name)
        guard element.responds(to: selector) else { return nil }
        return element.perform(selector)?.takeUnretainedValue()
    }

    var elements: [NSObject] {
        var result: [NSObject] = []
        var seen = Set<ObjectIdentifier>()
        func walk(_ element: Any) {
            guard let node = element as? NSObject,
                  seen.insert(ObjectIdentifier(node)).inserted else { return }
            result.append(node)
            let children = (node as? any NSAccessibilityProtocol)?.accessibilityChildren()
                ?? attribute("accessibilityChildren", of: node) as? [Any]
                ?? node.accessibilityAttributeValue(.children) as? [Any] ?? []
            for child in children { walk(child) }
        }
        walk(view)
        return result
    }

    var text: String {
        elements.flatMap { element -> [String] in
            let modern = element as? any NSAccessibilityProtocol
            return [modern?.accessibilityLabel(), modern?.accessibilityValue() as? String,
                    attribute("accessibilityLabel", of: element) as? String,
                    attribute("accessibilityValue", of: element) as? String,
                    element.accessibilityAttributeValue(.title) as? String,
                    element.accessibilityAttributeValue(.description) as? String,
                    element.accessibilityAttributeValue(.value) as? String].compactMap { $0 }
        }.joined(separator: "\n")
    }

    /// Invokes a VoiceOver custom action exposed by a hosted control.
    func performCustomAction(named name: String) -> Bool {
        for element in elements {
            let actions: [NSAccessibilityCustomAction]
            if let modern = element as? any NSAccessibilityProtocol,
               let axActions = modern.accessibilityCustomActions() {
                actions = axActions
            } else if let axActions = attribute("accessibilityCustomActions", of: element) as? [NSAccessibilityCustomAction] {
                actions = axActions
            } else {
                continue
            }
            for action in actions where action.name == name {
                if let handler = action.handler {
                    return handler() ?? true
                }
                let perform = NSSelectorFromString("perform")
                if action.responds(to: perform) {
                    _ = action.perform(perform)
                    return true
                }
            }
        }
        return false
    }

    /// Steps an adjustable control (e.g. a scrubber) via VoiceOver increment.
    func incrementAccessibility(labeled label: String) -> Bool {
        for element in elements {
            guard let modern = element as? any NSAccessibilityProtocol, modern.accessibilityLabel() == label else { continue }
            let increment = NSSelectorFromString("accessibilityIncrement")
            if element.responds(to: increment) {
                _ = element.perform(increment)
                return true
            }
        }
        return false
    }

    var customActionNames: [String] {
        elements.flatMap { element -> [String] in
            if let actions = (element as? any NSAccessibilityProtocol)?.accessibilityCustomActions() {
                return actions.map(\.name)
            }
            if let actions = attribute("accessibilityCustomActions", of: element) as? [NSAccessibilityCustomAction] {
                return actions.map(\.name)
            }
            let customActions = NSAccessibility.Attribute(rawValue: "AXCustomActions")
            if let actions = element.accessibilityAttributeValue(customActions) as? [NSAccessibilityCustomAction] {
                return actions.map(\.name)
            }
            return []
        }
    }
}

/// A synthetic mouse event at `point` in `window` (pressure 0 on mouse up).
func testMouseEvent(_ type: NSEvent.EventType, _ point: NSPoint, in window: NSWindow,
                    modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
    try #require(NSEvent.mouseEvent(
        with: type, location: point, modifierFlags: modifiers, timestamp: 0,
        windowNumber: window.windowNumber, context: nil, eventNumber: 0,
        clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1
    ))
}
