//
//  AppDelegate.swift
//  ARMEmulator
//
//  Created by Grant Savage on 2/27/19.
//  Copyright © 2019 Grant Savage. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
	func applicationDidFinishLaunching(_ aNotification: Notification) {
		// Insert code here to initialize your application
	}

	func applicationWillTerminate(_ aNotification: Notification) {
		// Insert code here to tear down your application
		if let vc: ViewController = (NSApplication.shared.mainWindow?.contentViewController as? ViewController) {
			vc.exit()
		}
	}
}

