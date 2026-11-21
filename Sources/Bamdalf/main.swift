import AppKit
import BamdalfKit

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    private let referenceCreation = ReferenceCreationController()
    private var viewer: ViewerWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        viewer = ViewerWindowController(session: ViewerSession(), referenceCreation: referenceCreation)
        installMenus()
        viewer?.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        referenceCreation.requestTermination { sender.reply(toApplicationShouldTerminate: $0) }
    }

    private func installMenus() {
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "bamdalf")
        applicationMenu.addItem(withTitle: "Quit bamdalf", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)

        let fileItem = NSMenuItem()
        fileItem.submenu = viewer?.makeFileMenu()
        menu.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        menu.addItem(editItem)

        let goItem = NSMenuItem()
        goItem.submenu = viewer?.makeGoMenu()
        menu.addItem(goItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        NSApplication.shared.windowsMenu = windowMenu
        NSApplication.shared.mainMenu = menu
    }
}

let application = NSApplication.shared
let delegate = ApplicationDelegate()
application.setActivationPolicy(.regular)
application.delegate = delegate
application.run()
