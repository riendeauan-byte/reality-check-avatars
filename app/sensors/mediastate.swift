// Reports whether the camera and/or microphone are currently in use, by
// querying the hardware "is running somewhere" state. That state query needs
// no camera/mic permission (we never touch frames or samples).
//
// Prints exactly: "camera=<0|1> mic=<0|1>"
//
// Build: swiftc -O -o mediastate mediastate.swift
import CoreAudio
import CoreMediaIO
import Foundation

// MARK: microphone (CoreAudio)
func micActive() -> Bool {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return false }
    let count = Int(size) / MemoryLayout<AudioObjectID>.size
    var ids = [AudioObjectID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return false }

    for id in ids {
        // only devices that actually have input streams are microphones
        var inAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var streamSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &inAddr, 0, nil, &streamSize) == noErr,
              streamSize > 0 else { continue }

        var running: UInt32 = 0
        var rSize = UInt32(MemoryLayout<UInt32>.size)
        var rAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(id, &rAddr, 0, nil, &rSize, &running) == noErr, running != 0 {
            return true
        }
    }
    return false
}

// MARK: camera (CoreMediaIO)
func cameraActive() -> Bool {
    var addr = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    var size: UInt32 = 0
    guard CMIOObjectGetPropertyDataSize(
        CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &size) == noErr else { return false }
    let count = Int(size) / MemoryLayout<CMIOObjectID>.size
    if count == 0 { return false }
    var ids = [CMIOObjectID](repeating: 0, count: count)
    var used: UInt32 = 0
    guard CMIOObjectGetPropertyData(
        CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, size, &used, &ids) == noErr else { return false }

    for id in ids {
        var running: UInt32 = 0
        var rSize = UInt32(MemoryLayout<UInt32>.size)
        var rUsed: UInt32 = 0
        var rAddr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        if CMIOObjectGetPropertyData(id, &rAddr, 0, nil, rSize, &rUsed, &running) == noErr, running != 0 {
            return true
        }
    }
    return false
}

print("camera=\(cameraActive() ? 1 : 0) mic=\(micActive() ? 1 : 0)")
