//
//  Extensions.swift
//  ARMEmulator
//
//  Created by Grant Savage on 3/17/19.
//  Copyright © 2019 Grant Savage. All rights reserved.
//

import Cocoa

extension NSButton {
	func setState(text: String, enabled: Bool) {
		self.title = text
		self.isEnabled = enabled
	}
}

extension NSProgressIndicator {
	func toggle(loading: Bool) {
		self.isHidden = !loading
		loading ? self.startAnimation(self) : self.stopAnimation(self)
	}
}

extension NSTextField {
	func setState(text: String, color: NSColor?) {
		if let color = color {
			self.textColor = color
		}
		self.stringValue = text
	}
}
