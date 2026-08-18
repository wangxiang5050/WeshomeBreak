import AppKit
import Testing
@testable import WeshomeBreak

@Suite("SettingsEditingClick")
@MainActor
struct SettingsEditingClickTests {

    @Test("a click on the title TextField or its field editor keeps editing")
    func textInputKeepsEditing() {
        #expect(!SettingsEditingClick.shouldResignTitleEditing(hitView: NSTextField()))
        #expect(!SettingsEditingClick.shouldResignTitleEditing(hitView: NSTextView()))
        let nested = NSView()
        let field = NSTextField(string: "小星星")
        field.addSubview(nested)
        #expect(!SettingsEditingClick.shouldResignTitleEditing(hitView: nested))
    }

    @Test("a click on empty chrome or other controls ends editing")
    func outsideTextInputEndsEditing() {
        #expect(SettingsEditingClick.shouldResignTitleEditing(hitView: NSView()))
        #expect(SettingsEditingClick.shouldResignTitleEditing(hitView: NSButton()))
        #expect(SettingsEditingClick.shouldResignTitleEditing(hitView: nil))
    }
}
