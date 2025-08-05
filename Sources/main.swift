import Foundation
import IOKit.hid
import CoreMIDI

// MARK: - MIDI helper

class MIDIVirtualSender {
    private var client = MIDIClientRef()
    private var virtualSource: MIDIEndpointRef = 0

    init(name: String) {
        MIDIClientCreate(name as CFString, nil, nil, &client)
        // create virtual source (appears as MIDI IN to DAW)
        MIDISourceCreate(client, name as CFString, &virtualSource)
        print("Created virtual MIDI source '\(name)'")
    }

    /// send single note on/off
    func send(note: UInt8, velocity: UInt8, channel: UInt8 = 0, isOn: Bool) {
        let status: UInt8 = (isOn ? 0x90 : 0x80) | (channel & 0x0F)
        let data: [UInt8] = [status, note & 0x7F, velocity & 0x7F]

        var packetList = MIDIPacketList()
        withUnsafeMutablePointer(to: &packetList) { plPtr in
            var pkt = MIDIPacketListInit(plPtr)
            pkt = MIDIPacketListAdd(plPtr, 1024, pkt, 0, data.count, data)
            // Send to virtual source
            MIDIReceived(virtualSource, plPtr)
        }
    }
}
// MARK: - PS4 Controller parsing skeleton

// NOTE: 这个部分的 report layout 依你实际拿到的 PS4 控制器输入而定。
// 建议你先 dump 报文（例如用简单打印每次收到的 raw bytes），确认 L2/R2 在哪个 offset。
// 下面假设 analog trigger （L2 / R2）是从某个 byte 读取 0~255。

class DS4Reader {
    private var manager: IOHIDManager
    private let midi: MIDIVirtualSender

    // track last velocity to emit note off when released
    private var lastL2Velocity: UInt8 = 0
    private var lastR2Velocity: UInt8 = 0
    private let kickNote: UInt8 = 36  // MIDI note for Kick
    private let snareNote: UInt8 = 38 // MIDI note for Snare

    init(midiSender: MIDIVirtualSender) {
        self.midi = midiSender
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        // Only match Sony devices (PS4 DualShock 4)
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x054C
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        // log when devices appear/disappear
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, sender, device in
            print("HID device connected: \(device)")
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, result, sender, device in
            print("HID device removed: \(device)")
        }, context)

        IOHIDManagerRegisterInputValueCallback(manager, { context, result, sender, value in
            let myself = Unmanaged<DS4Reader>.fromOpaque(context!).takeUnretainedValue()
            myself.handle(value: value)
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        let ret = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if ret != kIOReturnSuccess {
            print("Failed to open HID manager: \(ret)")
        } else {
            print("HID manager opened.")
        }
    }

    private func handle(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        // Filter: only care about Generic Desktop page (0x01) = axes/triggers; ignore keyboard noise
        guard usagePage == 0x01 || usagePage == 0x09 else { return }
        let intValue = IOHIDValueGetIntegerValue(value)

        // DEBUG: dump all incoming HID element info so you can identify L2 / R2
        // print(String(format: "HID dump: usage=0x%02X value=%d", usage, intValue))

        // placeholder logic: once you know real usage values for L2/R2, replace 0x32/0x33 below
        if usagePage == 0x01 {
            if usage == 0x33 { // actual L2
                let vel = scaledVelocity(from: Int(intValue))
                processTrigger(velocity: vel, lastVelocity: &lastL2Velocity, note: snareNote)
            } else if usage == 0x34 { // actual R2
                let vel = scaledVelocity(from: Int(intValue))
                processTrigger(velocity: vel, lastVelocity: &lastR2Velocity, note: kickNote)
            }
        } else if usagePage == 0x09 {
            handleButton(usage: usage, pressed: intValue != 0)
        }
    }

    private func scaledVelocity(from analog: Int) -> UInt8 {
        // 假设 analog 0..255 映射到 0..127
        let v = min(max(analog, 0), 255)
        return UInt8((Double(v) / 255.0) * 127.0)
    }

    private func processTrigger(velocity: UInt8, lastVelocity: inout UInt8, note: UInt8) {
        let pressTh: UInt8 = 15
        let relTh: UInt8 = 8
        if velocity >= pressTh && lastVelocity < pressTh {
            midi.send(note: note, velocity: velocity, isOn: true)
        } else if velocity <= relTh && lastVelocity > relTh {
            midi.send(note: note, velocity: 0, isOn: false)
        }
        lastVelocity = velocity
    }

    private let buttonNotes: [UInt32: UInt8] = [
        0x01: 42, // Square → Closed HH
        0x02: 46, // Cross  → Open HH
        0x03: 49, // Circle → Crash
        0x04: 51, // Triangle → Ride
        0x05: 37, // L1 → Rim
        0x06: 40, // R1 → Snare (rim)
        0x0B: 75, // L3 → Clave
        0x0C: 39  // R3 → Clap
    ]
    private var pressedButtons = Set<UInt32>()

    private func handleButton(usage: UInt32, pressed: Bool) {
        guard let note = buttonNotes[usage] else { return }
        if pressed {
            if !pressedButtons.contains(usage) {
                pressedButtons.insert(usage)
                midi.send(note: note, velocity: 100, isOn: true)
            }
        } else {
            if pressedButtons.remove(usage) != nil {
                midi.send(note: note, velocity: 0, isOn: false)
            }
        }
    }
}

// MARK: - Run

let midiSender = MIDIVirtualSender(name: "DS4toMIDI")
let reader = DS4Reader(midiSender: midiSender)

print("Running. Make sure your PS4 controller is connected and in a mode the system recognizes (USB/Bluetooth).")
CFRunLoopRun()