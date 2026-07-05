import Foundation

struct DockRestoreSnapshot: Codable, Equatable {
    var createdAt: Date
    var appVersion: String
    var values: [String: DockPreferenceValue]
    var capturedKeys: [String]? = nil
}

enum DockPreferenceValue: Codable, Equatable {
    case bool(Bool)
    case double(Double)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }

    func matches(rawValue: Any?) -> Bool {
        switch self {
        case .bool(let expectedBool):
            if let bool = rawValue as? Bool {
                return bool == expectedBool
            }
            if let number = rawValue as? NSNumber {
                return number.boolValue == expectedBool
            }
            return false
        case .double(let expectedDouble):
            guard let actualDouble = Self.double(from: rawValue) else {
                return false
            }
            return abs(actualDouble - expectedDouble) < Self.matchTolerance
        case .string(let expectedString):
            return rawValue as? String == expectedString
        }
    }

    static func double(from rawValue: Any?) -> Double? {
        if let value = rawValue as? Double {
            return value
        }
        if let value = rawValue as? Int {
            return Double(value)
        }
        if let value = rawValue as? NSNumber {
            return value.doubleValue
        }
        return nil
    }

    static let matchTolerance = 0.000_001
}
