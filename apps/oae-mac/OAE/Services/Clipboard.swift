import AppKit

public enum Clipboard {
    public static func copy(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }

    /// Copy + optionally simulate Cmd+V into the frontmost app.
    public static func copyAndPaste(_ string: String, autoPaste: Bool) {
        copy(string)
        guard autoPaste else { return }
        // Small delay so the target app has time to receive focus-changed
        // notifications before we synthesize the paste.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            HotkeyManager.simulatePaste()
        }
    }
}
