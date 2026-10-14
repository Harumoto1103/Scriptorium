// Tiny Text Input Sources helper:  swift tis.swift register <app> | enable | select <Latin|Greek> | list | disable
import Carbon
import Foundation

let prefix = "uk.harukita.inputmethod.Scriptorium"
let args = CommandLine.arguments.dropFirst()

func sources() -> [TISInputSource] {
    let filter = [kTISPropertyBundleID as String: prefix] as CFDictionary
    return (TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]) ?? []
}
func prop(_ s: TISInputSource, _ k: CFString) -> String {
    guard let p = TISGetInputSourceProperty(s, k) else { return "?" }
    let v = Unmanaged<AnyObject>.fromOpaque(p).takeUnretainedValue()
    return "\(v)"
}

switch args.first {
case "register":
    let st = TISRegisterInputSource(URL(fileURLWithPath: args.dropFirst().first!) as CFURL)
    print("register:", st)
case "enable":
    for s in sources() { print("enable", prop(s, kTISPropertyInputSourceID), TISEnableInputSource(s)) }
case "disable":
    for s in sources() { print("disable", prop(s, kTISPropertyInputSourceID), TISDisableInputSource(s)) }
case "select":
    let want = prefix + "." + (args.dropFirst().first ?? "Latin")
    for s in sources() where prop(s, kTISPropertyInputSourceID) == want { print("select", want, TISSelectInputSource(s)) }
case "current":
    let s = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    print(prop(s, kTISPropertyInputSourceID))
default:
    for s in sources() {
        print(prop(s, kTISPropertyInputSourceID), "enabled=\(prop(s, kTISPropertyInputSourceIsEnabled))",
              "selectable=\(prop(s, kTISPropertyInputSourceIsSelectCapable))")
    }
}
