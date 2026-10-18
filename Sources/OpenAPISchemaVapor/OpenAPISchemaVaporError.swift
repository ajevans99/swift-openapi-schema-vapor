public enum OpenAPISchemaVaporError: Error, Equatable, CustomStringConvertible {
  case unsupportedHTTPMethod(method: String, path: String)
  case duplicateParameter(operationID: String, name: String, location: String)
  case unknownPathParameter(operationID: String, path: String, name: String)
  case conflictingComponentSchema(name: String)
  case duplicateSecurityScheme(name: String)
  case unknownSecurityScheme(operationID: String, scheme: String)
  case emptySecurityRequirement(operationID: String)
  case invalidExtensionKey(operationID: String, key: String)
  case routeOutsidePrefix(operationID: String, path: String, prefix: String)
  case nonConstantPrefix(prefix: String)
  case unsupportedPathComponent(operationID: String, path: String, component: String)

  public var description: String {
    switch self {
    case .unsupportedHTTPMethod(let method, let path):
      return "HTTP method \(method) on '\(path)' has no OpenAPI operation counterpart."
    case .duplicateParameter(let operationID, let name, let location):
      return "Operation '\(operationID)' documents \(location) parameter '\(name)' more than once."
    case .unknownPathParameter(let operationID, let path, let name):
      return
        "Operation '\(operationID)' documents path parameter '\(name)', but route '\(path)' has no ':\(name)' component."
    case .conflictingComponentSchema(let name):
      return "Different schemas are registered under component name '\(name)'."
    case .duplicateSecurityScheme(let name):
      return "Security scheme '\(name)' is registered more than once."
    case .unknownSecurityScheme(let operationID, let scheme):
      return "Operation '\(operationID)' requires unregistered security scheme '\(scheme)'."
    case .emptySecurityRequirement(let operationID):
      return
        "Operation '\(operationID)' requires security without alternatives; use .anonymous for operations without credentials."
    case .invalidExtensionKey(let operationID, let key):
      return
        "Operation '\(operationID)' extension '\(key)' must start with 'x-' and must not use the reserved 'x-oai-' or 'x-oas-' prefixes."
    case .routeOutsidePrefix(let operationID, let path, let prefix):
      return "Operation '\(operationID)' route '\(path)' does not start with document prefix '\(prefix)'."
    case .nonConstantPrefix(let prefix):
      return "Document prefix '\(prefix)' must contain only constant path components."
    case .unsupportedPathComponent(let operationID, let path, let component):
      return
        "Operation '\(operationID)' route '\(path)' uses '\(component)', which has no OpenAPI path template equivalent."
    }
  }
}
