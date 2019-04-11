//
//  ViewController.swift
//  ARMEmulator
//
//  Created by Grant Savage on 2/27/19.
//  Copyright © 2019 Grant Savage. All rights reserved.
//

import Cocoa
import SocketSwift

class ViewController: NSViewController {
	// Status labels
	@IBOutlet var connectionStatusLabel: NSTextField!
	@IBOutlet var lidarStatusLabel: NSTextField!
	@IBOutlet var sonarStatusLabel: NSTextField!
	@IBOutlet var reportingStatusLabel: NSTextField!
	@IBOutlet var dataLoggingStatusLabel: NSTextField!
	@IBOutlet var batteryStatusLabel: NSTextField!
	@IBOutlet var calibrationStatusLabel: NSTextField!
	
	// Data labels
	@IBOutlet var altitudeLabel: NSTextField!
	@IBOutlet var lidarDataLabel: NSTextField!
	@IBOutlet var sonarDataLabel: NSTextField!
	
	// Loaders
	@IBOutlet var calibrateButtonLoader: NSProgressIndicator!
	
	// Buttons
	@IBOutlet var calibrateButton: NSButton!
	@IBOutlet var reportingToggleButton: NSButton!
	@IBOutlet var dataLoggingToggleButton: NSButton!
	@IBOutlet var connectButton: NSButton!
	@IBOutlet var getStatusButton: NSButton!
	
	// Progress Views/Level Indicators
	@IBOutlet var batteryLevelIndicator: NSLevelIndicator!
	
	// Properties
	var client: Socket!
	var reporting = false
	var dataLogging = false
	var reconnectTimer: Timer?
	var reconnectAttempts = 0
	let bufferSize = 128
	
	// App startup
	override func viewDidLoad() {
		super.viewDidLoad()
		
		// View and button setup
		calibrateButton.action = #selector(self.sendCalibrationEvent)
		reportingToggleButton.action = #selector(self.sendReportingToggleEvent)
		getStatusButton.action = #selector(self.sendGetStatusEvent)
		dataLoggingToggleButton.action = #selector(self.sendToggleDataLogging)
		connectButton.action = #selector(self.handleConnectButttonPress)
		connectionStatusLabel.textColor = .red
		connectionStatusLabel.stringValue = "Disconnected"
		calibrateButtonLoader.isHidden = true
		calibrationStatusLabel.isHidden = true
		
		// Start the TCP Socket client
		self.startClient()
	}
	
	// Handle an incoming message
	func handleEvent(event: String.SubSequence?, data: String.SubSequence?) {
		switch event {
			case "altitude":
				self.altitudeLabel.stringValue = "Altitude: \(data ?? "") cm"
			case "lidarData":
				self.lidarDataLabel.stringValue = "LIDAR: \(data ?? "") cm"
			case "sonarData":
				self.sonarDataLabel.stringValue = "SONAR: \(data ?? "") cm"
			case "calibrationStatus":
				if let data = data {
					if let returnCode = getReturnCode(substring: data) {
						self.calibrationStatusLabel.isHidden = false
						self.calibrateButtonLoader.toggle(loading: false)
						self.calibrateButton.setState(text: "Calibrate", enabled: true)
						switch returnCode {
							case 1:
								self.calibrationStatusLabel.setState(text: "Not Calibrated", color: .yellow)
							case 0:
								self.calibrationStatusLabel.setState(text: "Calibrated", color: .green)
							case -1:
								self.calibrationStatusLabel.setState(text: "Error Calibrating", color: .red)
								showAlert(title: "Calibration Failure", text: "The sensor module has encountered an error calibrating: The maximum allowable offset has been exceded", type: .critical)
							case -2:
								self.calibrationStatusLabel.setState(text: "Error Calibrating", color: .red)
								showAlert(title: "Calibration Failure", text: "The sensor module has encountered an error calibrating: The sensors have failed or are not responding.", type: .critical)
							default:
								print("Unrecognized calibrationStatus returnCode: \(returnCode)")
						}
					}
				}
			case "lidarStatus":
				if let data = data {
					if let returnCode = getReturnCode(substring: data) {
						switch returnCode {
							case 0:
								lidarStatusLabel.setState(text: "OK", color: .green)
							case -1:
								lidarStatusLabel.setState(text: "FAIL", color: .red)
							default:
								print("Unrecognized lidarStatus return code: \(returnCode)")
						}
					}
				}
			case "sonarStatus":
				if let data = data {
					if let returnCode = getReturnCode(substring: data) {
						switch returnCode {
							case 0:
								sonarStatusLabel.setState(text: "OK", color: .green)
							case -1:
								sonarStatusLabel.setState(text: "FAIL", color: .red)
							case -2:
								sonarStatusLabel.setState(text: "FAIL", color: .red)
							case -3:
								sonarStatusLabel.setState(text: "NO DATA", color: .red)
							default:
								print("Unrecognized sonarStatus return code")
						}
					}
				}
			case "reportingStatus":
				if let data = data {
					if let returnCode = getReturnCode(substring: data) {
						switch returnCode {
						case 1:
							reporting = true
							reportingStatusLabel.setState(text: "ON", color: .green)
						case 0:
							reporting = false
							reportingStatusLabel.setState(text: "OFF", color: .yellow)
						default:
							print("Unrecognized reportingStatus return code")
						}
					}
				}
			case "loggingStatus":
				if let data = data {
					if let returnCode = getReturnCode(substring: data) {
						switch returnCode {
						case 1:
							dataLogging = true
							dataLoggingStatusLabel.setState(text: "ON", color: .green)
						case 0:
							dataLogging = false
							dataLoggingStatusLabel.setState(text: "OFF", color: .yellow)
						default:
							print("Unrecognized reportingStatus return code")
						}
					}
				}
			case "batteryStatus":
				if let data = data {
					if data.first == "-" {
						if let returnCode = getReturnCode(substring: data) {
							if returnCode == -1 {
								print("Battery status unavailable.");
								batteryStatusLabel.stringValue = "Battery: NO DATA"
								batteryLevelIndicator.stringValue = "0"
								batteryLevelIndicator.isHidden = true
								return;
							}
						}
					}
					batteryLevelIndicator.isHidden = false
					batteryStatusLabel.stringValue = "Battery: \(data)%"
					if let batP = Int(data) {
						batteryLevelIndicator.stringValue = "\(batP / 10))"
					}
				}
			default:
				print("Unrecognized Event: \(event ?? ""):\(data ?? "")")
		}
	}
	
	// Parse return code from received status message
	func getReturnCode(substring: String.SubSequence) -> Int? {
		let convertedString = String(substring)
		let firstCharacter = convertedString.first
		if firstCharacter == "-" {
			let negativeStringIndex = convertedString.index(convertedString.startIndex, offsetBy: 2)
			let negativeString = convertedString[..<negativeStringIndex]
			return Int(negativeString)
		}
		
		return Int(String(firstCharacter!))
	}
	
	// Start the TCP client, listen for messages, and handle reconnection interval
	func startClient() {
		do {
			// Initialize new socket
			if self.client == nil {
				self.client = try Socket(.inet, type: .stream, protocol: .tcp)
			}
			
			var connectionAddress = "127.0.0.1"
			if let address = ProcessInfo.processInfo.environment["ASM_IP"] {
				print("Setting address to \(address)")
				connectionAddress = address;
			}
			
			// Try to connect
			try self.client.connect(port: 4000, address: connectionAddress)
		} catch {
			// Close the socket if connection can't be established
			if self.client != nil {
				self.client.close();
			}
			
			// Deinit client
			self.client = nil
			
			print("Unable to connect");
			return;
		}
		
		print("Connected!");
		
		connectButton.isEnabled = false
		
		// Invalidate reconnect interval
		if self.reconnectTimer != nil {
			self.reconnectTimer?.invalidate()
			self.reconnectTimer = nil
		}
		
		self.reconnectAttempts = 0;
		
		// Update UI state
		DispatchQueue.main.async {
			self.connectionStatusLabel.setState(text: "Connected", color: .green)
		}
		
		self.sendGetStatusEvent()
		
		// Allocate receive buffer
		var buffer = [UInt8](repeating: 0, count: self.bufferSize)
		
		// Dispatch new background thread
		DispatchQueue.global().async {
			do {
				// Read socket buffer until no more bytes available
				while try self.client.read(&buffer, size: self.bufferSize) > 0 {
					// Decode Base64 string
					if let response = String(bytes: buffer, encoding: .utf8) {
						let sanitizedString = response.replacingOccurrences(of: "\0", with: "").replacingOccurrences(of: "\04", with: "").dropLast()
						// Parse response string
						let events = sanitizedString.split(separator: "|")
						for event in events {
							let parts = event.split(separator: ":")
							// Handle each parsed event
							DispatchQueue.main.async {
								self.handleEvent(event: parts.first, data: parts.last)
							}
						}
					}
				
					// Reset the buffer
					buffer = [UInt8](repeating: 0, count: self.bufferSize)
				}
				
				print("Disconnected!")
				
				// Update UI and start reconnect interval
				if self.reconnectAttempts <= 5 {
					DispatchQueue.main.async {
						self.connectionStatusLabel.setState(text: "Reconnecting", color: .yellow)
						
						// Check if reconnect interval exists
						if self.reconnectTimer == nil {
							print("Initializing reconnect interval...");
							self.reconnectTimer = Timer.scheduledTimer(timeInterval: 5.0, target: self, selector: #selector(self.attemptReconnect), userInfo: nil, repeats: true)
							self.reconnectTimer?.tolerance = 0.1
						}
					}
				}
			} catch (let err) {
				print(err.localizedDescription)
			}
		} // End DispatchQueue.global().async
	}
	
	// Attempts reconnect of the TCP socket
	@objc func attemptReconnect() {
		if self.reconnectAttempts <= 5 {
			print("Attempting reconnect...")
			self.startClient()
			self.reconnectAttempts += 1
		} else {
			self.reconnectTimer?.invalidate()
			self.connectionStatusLabel.setState(text: "Disconnected", color: .red);
			self.connectButton.isEnabled = true
			self.reconnectTimer = nil
		}
	}

	// Sends the calibration event to the ASM
	@objc func sendCalibrationEvent() {
		self.calibrateButton.setState(text: "Calibrate", enabled: false)
		self.calibrateButtonLoader.toggle(loading: true)
		self.calibrationStatusLabel.isHidden = true
		sendEvent(event: "calibrate", data: 1)
	}

	// Sends the reportingToggle event to the ASM
	@objc func sendReportingToggleEvent() {
		reporting = !reporting
		sendEvent(event: "reportingToggle", data: reporting ? 1 : 0)
	}
	
	// Sends the getStatus event to the ASM
	@objc func sendGetStatusEvent() {
		sendEvent(event: "getStatus", data: 0)
	}

	// Sends the loggingToggle event to the ASM
	@objc func sendToggleDataLogging() {
		dataLogging = !dataLogging
		sendEvent(event: "loggingToggle", data: dataLogging ? 1 : 0)
	}
	
	@objc func handleConnectButttonPress() {
		self.reconnectAttempts = 0
		self.startClient()
	}
	
	// Encodes a string to send over the TCP socket
	func encodeMessage(message: String) -> [UInt8] {
		return ([UInt8])(message.utf8)
	}
	
	// Shows an on screen alert modal
	func showAlert(title: String, text: String, type: NSAlert.Style) {
		let alert = NSAlert()
		alert.alertStyle = type
		alert.messageText = title
		alert.informativeText = text
		alert.addButton(withTitle: "OK")
		alert.runModal()
	}
	
	// Closes socket before the application quits
	func exit() {
		print("Quitting...")
		if self.client != nil {
			self.client.close()
		}
	}
	
	// Sends an event over the TCP stream
	func sendEvent(event: String, data: Int) {
		do {
			let encodedString = "\(event):\(data)"
			try self.client.write(encodeMessage(message: encodedString))
		} catch (let err) {
			print("Error sending \(event) event: \(err.localizedDescription)")
		}
	}
}
