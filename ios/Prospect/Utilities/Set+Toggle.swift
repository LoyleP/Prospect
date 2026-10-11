// Utilities/Set+Toggle.swift
// Shared helper for filter pill toggles.
import Foundation

extension Set {
    mutating func toggle(member: Element, isOn: Bool) {
        if isOn { insert(member) } else { remove(member) }
    }
}
