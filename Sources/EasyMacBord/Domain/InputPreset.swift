import Foundation

struct InputPreset: Codable, Equatable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case fixedText
        case keyChord

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fixedText: "固定文本"
            case .keyChord: "键盘组合键"
            }
        }

        var bindingKind: BindingKind {
            switch self {
            case .fixedText: .fixedText
            case .keyChord: .keyChord
            }
        }
    }

    let id: UUID
    var kind: Kind
    var title: String
    var value: String

    init(id: UUID = UUID(), kind: Kind, title: String, value: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.value = value
    }

    func makeBinding() -> ActionBinding {
        ActionBinding(kind: kind.bindingKind, value: value, title: title)
    }
}

enum InputPresetTemplate: String, CaseIterable, Identifiable {
    case cut
    case delete
    case returnKey
    case focusSearch
    case switchInputSource

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cut: "剪切"
        case .delete: "删除"
        case .returnKey: "回车"
        case .focusSearch: "聚焦搜索"
        case .switchInputSource: "切换输入法"
        }
    }

    var chord: String {
        switch self {
        case .cut: "Meta+X"
        case .delete: "Backspace"
        case .returnKey: "Return"
        case .focusSearch: "Meta+Space"
        case .switchInputSource: "Ctrl+Space"
        }
    }

    var symbol: String {
        switch self {
        case .cut: "scissors"
        case .delete: "delete.left"
        case .returnKey: "return"
        case .focusSearch: "magnifyingglass"
        case .switchInputSource: "character.cursor.ibeam"
        }
    }
}

enum KeyChord {
    struct Modifiers: OptionSet, Equatable, Sendable {
        let rawValue: UInt

        static let meta = Modifiers(rawValue: 1 << 0)
        static let control = Modifiers(rawValue: 1 << 1)
        static let option = Modifiers(rawValue: 1 << 2)
        static let shift = Modifiers(rawValue: 1 << 3)
        static let function = Modifiers(rawValue: 1 << 4)
    }

    enum Key: Equatable, Sendable {
        case letter(String)
        case digit(String)
        case space
        case tab
        case `return`
        case escape
        case backspace
        case arrowLeft
        case arrowRight
        case arrowUp
        case arrowDown
        case function(Int)

        fileprivate var token: String? {
            switch self {
            case .letter(let value):
                let token = value.uppercased()
                return token.count == 1 && token.unicodeScalars.allSatisfy { $0.isASCII } ? token : nil
            case .digit(let value):
                return value.count == 1 && value.allSatisfy { $0.isNumber } ? value : nil
            case .space: return "Space"
            case .tab: return "Tab"
            case .return: return "Return"
            case .escape: return "Escape"
            case .backspace: return "Backspace"
            case .arrowLeft: return "ArrowLeft"
            case .arrowRight: return "ArrowRight"
            case .arrowUp: return "ArrowUp"
            case .arrowDown: return "ArrowDown"
            case .function(let number) where (1...12).contains(number): return "F\(number)"
            case .function: return nil
            }
        }
    }

    static func make(modifiers: Modifiers, key: Key?) -> String? {
        guard !modifiers.contains(.function), let key, let keyToken = key.token else { return nil }
        var tokens: [String] = []
        if modifiers.contains(.meta) { tokens.append("Meta") }
        if modifiers.contains(.control) { tokens.append("Ctrl") }
        if modifiers.contains(.option) { tokens.append("Alt") }
        if modifiers.contains(.shift) { tokens.append("Shift") }
        tokens.append(keyToken)
        return tokens.joined(separator: "+")
    }

    static func key(forKeyCode keyCode: UInt16) -> Key? {
        switch keyCode {
        case 0: .letter("a")
        case 1: .letter("s")
        case 2: .letter("d")
        case 3: .letter("f")
        case 4: .letter("h")
        case 5: .letter("g")
        case 6: .letter("z")
        case 7: .letter("x")
        case 8: .letter("c")
        case 9: .letter("v")
        case 11: .letter("b")
        case 12: .letter("q")
        case 13: .letter("w")
        case 14: .letter("e")
        case 15: .letter("r")
        case 16: .letter("y")
        case 17: .letter("t")
        case 18: .digit("1")
        case 19: .digit("2")
        case 20: .digit("3")
        case 21: .digit("4")
        case 22: .digit("6")
        case 23: .digit("5")
        case 25: .digit("9")
        case 26: .digit("7")
        case 28: .digit("8")
        case 29: .digit("0")
        case 31: .letter("o")
        case 32: .letter("u")
        case 34: .letter("i")
        case 35: .letter("p")
        case 36: .return
        case 37: .letter("l")
        case 38: .letter("j")
        case 40: .letter("k")
        case 45: .letter("n")
        case 46: .letter("m")
        case 48: .tab
        case 49: .space
        case 51: .backspace
        case 53: .escape
        case 96: .function(5)
        case 97: .function(6)
        case 98: .function(7)
        case 99: .function(3)
        case 100: .function(8)
        case 101: .function(9)
        case 103: .function(11)
        case 109: .function(10)
        case 111: .function(12)
        case 118: .function(4)
        case 120: .function(2)
        case 122: .function(1)
        case 123: .arrowLeft
        case 124: .arrowRight
        case 125: .arrowDown
        case 126: .arrowUp
        default: nil
        }
    }
}
