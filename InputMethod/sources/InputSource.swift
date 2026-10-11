//
//  InputSource.swift
//  Squirrel
//
//  Created by Leo Liu on 5/10/24.
//

import Foundation
import InputMethodKit

final class SquirrelInstaller {
  enum InputMode: String, CaseIterable {
    static let primary = Self.hans
    case hans = "com.roarkist.inputmethod.RoarkT.pinyin"
    case flypy = "com.roarkist.inputmethod.RoarkT.flypy"
  }

  func enabledModes() -> [InputMode] {
    let sources = inputSources()
    return InputMode.allCases.filter { mode in
      guard let source = sources[mode.rawValue] else { return false }
      return getBool(for: source, key: kTISPropertyInputSourceIsEnabled) == true
    }
  }

  @discardableResult
  func register() -> Bool {
    let error = TISRegisterInputSource(SquirrelApp.appDir as CFURL)
    guard error == noErr else {
      print("Registration failed (\(error)) for input source at: \(SquirrelApp.appDir.path)")
      return false
    }
    let registered = InputMode.allCases.allSatisfy { waitForSource(mode: $0) != nil }
    print("Registration \(registered ? "verified" : "did not materialize") for input source at: \(SquirrelApp.appDir.path)")
    return registered
  }

  @discardableResult
  func enable(modes: [InputMode] = []) -> Bool {
    let modesToEnable = modes.isEmpty ? [.primary] : modes
    var operationSucceeded = true
    for mode in modesToEnable {
      guard let inputSource = inputSources()[mode.rawValue] else {
        print("Input source is not registered: \(mode.rawValue)")
        operationSucceeded = false
        continue
      }
      let error = TISEnableInputSource(inputSource)
      if error != noErr {
        print("Enable failed (\(error)) for input source: \(mode.rawValue)")
        operationSucceeded = false
      }
    }

    let verified = modesToEnable.allSatisfy { mode in
      guard let source = waitForSource(mode: mode) else { return false }
      return getBool(for: source, key: kTISPropertyInputSourceIsEnabled) == true
        && getBool(for: source, key: kTISPropertyInputSourceIsSelectCapable) == true
    }
    print("Enable \(operationSucceeded && verified ? "verified" : "not verified") for: \(modesToEnable.map(\.rawValue).joined(separator: ", "))")
    return operationSucceeded && verified
  }

  @discardableResult
  func select(mode: InputMode? = nil) -> Bool {
    let modeToSelect = mode ?? .primary
    if !enabledModes().contains(modeToSelect), !enable(modes: [modeToSelect]) {
      print("Cannot select an input source that is not enabled: \(modeToSelect.rawValue)")
      return false
    }
    guard let inputSource = inputSources()[modeToSelect.rawValue] else {
      print("Input source is not registered: \(modeToSelect.rawValue)")
      return false
    }

    if currentInputSourceID() != modeToSelect.rawValue {
      let error = TISSelectInputSource(inputSource)
      guard error == noErr else {
        print("Selection failed (\(error)) for input source: \(modeToSelect.rawValue)")
        return false
      }
    }

    for _ in 0..<10 {
      if currentInputSourceID() == modeToSelect.rawValue {
        print("Selection verified for input source: \(modeToSelect.rawValue)")
        return true
      }
      Thread.sleep(forTimeInterval: 0.1)
    }
    print("Selection did not become current for input source: \(modeToSelect.rawValue)")
    return false
  }

  @discardableResult
  func disable(modes: [InputMode] = []) -> Bool {
    let modesToDisable = modes.isEmpty ? InputMode.allCases : modes
    var succeeded = true
    for mode in modesToDisable {
      guard let inputSource = inputSources()[mode.rawValue] else { continue }
      if getBool(for: inputSource, key: kTISPropertyInputSourceIsEnabled) == true {
        let error = TISDisableInputSource(inputSource)
        if error != noErr {
          print("Disable failed (\(error)) for input source: \(mode.rawValue)")
          succeeded = false
        }
      }
    }
    return succeeded
  }

  private func waitForSource(mode: InputMode) -> TISInputSource? {
    for _ in 0..<10 {
      if let source = inputSources()[mode.rawValue] { return source }
      Thread.sleep(forTimeInterval: 0.1)
    }
    return nil
  }

  private func inputSources() -> [String: TISInputSource] {
    var result = [String: TISInputSource]()
    let sourceList = TISCreateInputSourceList(nil, true).takeRetainedValue() as! [TISInputSource]
    for inputSource in sourceList {
      let sourceIDRef = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID)
      guard let sourceID = unsafeBitCast(sourceIDRef, to: CFString?.self) as String? else { continue }
      result[sourceID] = inputSource
    }
    return result
  }

  func currentInputSourceID() -> String? {
    let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    let sourceIDRef = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
    return unsafeBitCast(sourceIDRef, to: CFString?.self) as String?
  }

  private func getBool(for inputSource: TISInputSource, key: CFString!) -> Bool? {
    let value = TISGetInputSourceProperty(inputSource, key)
    guard let boolean = unsafeBitCast(value, to: CFBoolean?.self) else { return nil }
    return CFBooleanGetValue(boolean)
  }
}
