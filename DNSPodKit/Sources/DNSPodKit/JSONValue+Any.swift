import Foundation

extension JSONValue {
  /// JSONSerialization tree → JSONValue (LLM clients parsing responses)
  public init?(any: Any) {
    switch any {
    case is NSNull: self = .null
    case let number as NSNumber:
      if number.isBoolean {
        self = .bool(number.boolValue)
      } else if let int = Int64(exactly: number) {
        self = .int(Int(int))
      } else if let double = Double(exactly: number) {
        self = .double(double)
      } else {
        self = .double(number.doubleValue)
      }
    case let string as String: self = .string(string)
    case let array as [Any]:
      var result: [JSONValue] = []
      for element in array {
        guard let value = JSONValue(any: element) else { return nil }
        result.append(value)
      }
      self = .array(result)
    case let object as [String: Any]:
      var result: [String: JSONValue] = [:]
      for (key, element) in object {
        guard let value = JSONValue(any: element) else { return nil }
        result[key] = value
      }
      self = .object(result)
    default: return nil
    }
  }

  /// JSONValue → JSONSerialization tree (building request bodies)
  public var anyValue: Any {
    switch self {
    case .null: NSNull()
    case .bool(let bool): bool
    case .int(let int): int
    case .double(let double): double
    case .string(let string): string
    case .array(let array): array.map(\.anyValue)
    case .object(let object): object.mapValues(\.anyValue)
    }
  }

  public var stringValue: String? {
    if case .string(let string) = self { return string }
    return nil
  }

  public var intValue: Int? {
    switch self {
    case .int(let int): int
    case .double(let double): Int(exactly: double.rounded())
    default: nil
    }
  }

  public var objectValue: [String: JSONValue]? {
    if case .object(let object) = self { return object }
    return nil
  }
}

private extension NSNumber {
  var isBoolean: Bool {
    CFGetTypeID(self) == CFBooleanGetTypeID()
  }
}
