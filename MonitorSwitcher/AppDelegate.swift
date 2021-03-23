//
//  AppDelegate.swift
//  MonitorSwitcher
//
//  Created by Kyle Partridge on 1/19/21.
//

import Cocoa
import SwiftUI


@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    let statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
    
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        if let button = statusItem.button {
            button.image = NSImage(named:NSImage.Name("StatusBarButtonImage"))
        }
        
        createMenu()
    }
    
    func createMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Switch Montiors", action: #selector(AppDelegate.switchMonitor(_:)), keyEquivalent: "P"))
        for (i, screen) in NSScreen.screens.enumerated() {
            var action: Selector;
            if i == 0 {
                action = #selector(AppDelegate.switchFirst(_:))
            } else {
                action = #selector(AppDelegate.switchSecond(_:))
            }
            
            menu.addItem(NSMenuItem(title: "\(screen.localizedName) - \(i)", action: action, keyEquivalent: "\(i)"))
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    @objc func queryMonitors(_ sender: Any?) {
        for screen in NSScreen.screens {
            print(screen)
        }
    }
    
    @objc func switchMonitor(_ sender: Any?) {
        for screen in NSScreen.screens {
            switchSingleMonitor(sender, screen: screen)
        }
    }
    
    @objc func switchFirst(_ sender: Any?) {
        switchSingleMonitor(sender, screen: NSScreen.screens[0])
    }
    
    @objc func switchSecond(_ sender: Any?) {
        switchSingleMonitor(sender, screen: NSScreen.screens[1])
    }
    
    @objc func switchSingleMonitor(_ sender: Any?, screen: NSScreen) {
        var command = DDCWriteCommand(control_id: UInt8(INPUT_SOURCE), new_value: UInt8(15))
        
        let description = screen.deviceDescription
        
        if description[NSDeviceDescriptionKey("NSDeviceIsScreen")] != nil {
            let screenNumber: UInt32 = description[NSDeviceDescriptionKey("NSScreenNumber")] as! UInt32
            
            print("screen", screenNumber)
            
            let devLoc = getDisplayDeviceLocation(screenNumber)!
            
            print(devLoc)
            
            let framebuffer = IOFramebufferPortFromCGDisplayID(screenNumber, devLoc as CFString)
            
            let result = DDCWrite(framebuffer, &command)
            if !result {
                print("failed to update")
            }
        }
    }
    
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
}

