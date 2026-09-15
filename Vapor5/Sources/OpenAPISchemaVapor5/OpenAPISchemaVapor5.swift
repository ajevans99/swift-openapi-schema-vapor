import Foundation
import JSONSchema
import JSONSchemaBuilder
import OpenAPISchema
import RoutingKit
import Vapor

public struct OpenAPIContractError: Error, Equatable, CustomStringConvertible {
  public let description: String

  public init(_ description: String) {
    self.description = description
  }
}

/// A deliberate JSON wire response, independent of Content's custom response encoders.
public struct JSONResponse<Value: Codable & Schemable & Sendable>: ResponseEncodable {
  public let value: Value
  public let status: Int

  public init(_ value: Value, status: Int = 200) {
    self.value = value
    self.status = status
  }

  public func encodeResponse(for request: Vapor.Request) async throws -> Vapor.Response {
    guard (200...599).contains(status), ![204, 205, 304].contains(status) else {
      throw OpenAPIContractError("JSONResponse requires a body-bearing HTTP status.")
    }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return Vapor.Response(
      status: .init(code: status),
      headers: [.contentType: "application/json"],
      body: .init(data: try encoder.encode(value))
    )
  }
}

struct Component: Sendable {
  let name: String
  let value: JSONValue

  init<T: Schemable>(_ type: T.Type, name: String?) {
    self.name = Schema(type, name: name).name
    self.value = T.schema.definition().jsonValue
  }
}

public struct OpenAPIRequestBody: Sendable {
  let body: Body
  let component: Component
  public let required: Bool

  public static func json<T: Codable & Schemable>(
    _ type: T.Type, name: String? = nil, required: Bool = true
  ) -> Self {
    Self(body: JSONBody(type, name: name), component: Component(type, name: name), required: required)
  }
}

public struct OpenAPIResponse: Sendable {
  public let status: Int
  public let description: String?
  let body: Body?
  let component: Component?

  public static func json<T: Codable & Schemable>(
    _ status: Int, _ type: T.Type, name: String? = nil, description: String? = nil
  ) -> Self {
    Self(
      status: status, description: description, body: JSONBody(type, name: name),
      component: Component(type, name: name)
    )
  }

  public static func empty(_ status: Int, description: String? = nil) -> Self {
    Self(status: status, description: description, body: nil, component: nil)
  }
}

public protocol OpenAPIParameterValue {
  static var openAPIParameterSchema: OpenAPISchemaValue { get }
}

extension String: OpenAPIParameterValue {
  public static var openAPIParameterSchema: OpenAPISchemaValue { .string() }
}

extension Int: OpenAPIParameterValue {
  public static var openAPIParameterSchema: OpenAPISchemaValue { .integer() }
}

extension Double: OpenAPIParameterValue {
  public static var openAPIParameterSchema: OpenAPISchemaValue { .number() }
}

extension Bool: OpenAPIParameterValue {
  public static var openAPIParameterSchema: OpenAPISchemaValue { .boolean }
}

extension UUID: OpenAPIParameterValue {
  public static var openAPIParameterSchema: OpenAPISchemaValue { .string(format: "uuid") }
}

public struct OpenAPIParameter: Sendable {
  public let name: String
  public let location: ParameterLocation
  public let required: Bool
  public let schema: OpenAPISchemaValue

  public init(
    _ name: String, in location: ParameterLocation, required: Bool,
    schema: OpenAPISchemaValue
  ) {
    self.name = name
    self.location = location
    self.required = required
    self.schema = schema
  }

  public static func path<T: OpenAPIParameterValue & LosslessStringConvertible>(
    _ name: String, _ type: T.Type
  ) -> Self {
    Self(name, in: .path, required: true, schema: T.openAPIParameterSchema)
  }

  public static func query<T: OpenAPIParameterValue>(
    _ name: String, _ type: T.Type, required: Bool = false
  ) -> Self {
    Self(name, in: .query, required: required, schema: T.openAPIParameterSchema)
  }

  public static func header<T: OpenAPIParameterValue>(
    _ name: String, _ type: T.Type, required: Bool = false
  ) -> Self {
    Self(name, in: .header, required: required, schema: T.openAPIParameterSchema)
  }
}

public enum OpenAPISecurity: Sendable {
  case publicAccess
  case required(String)
  case optional(String)

  var name: String? {
    switch self {
    case .publicAccess: nil
    case .required(let name), .optional(let name): name
    }
  }
}

public struct OpenAPIRouteDescriptor: Sendable {
  public let method: String
  public let path: [String]
  public let operationID: String
  public let parameters: [OpenAPIParameter]
  public let requestBody: OpenAPIRequestBody?
  public let responses: [OpenAPIResponse]
  public let security: OpenAPISecurity

  public init(
    method: String, path: [String], operationID: String,
    parameters: [OpenAPIParameter] = [],
    requestBody: OpenAPIRequestBody? = nil,
    responses: [OpenAPIResponse],
    security: OpenAPISecurity = .publicAccess
  ) {
    self.method = method
    self.path = path
    self.operationID = operationID
    self.parameters = parameters
    self.requestBody = requestBody
    self.responses = responses
    self.security = security
  }

  func prefixed(_ prefix: [String]) -> Self {
    Self(
      method: method, path: prefix + path, operationID: operationID, parameters: parameters,
      requestBody: requestBody, responses: responses, security: security
    )
  }
}

public protocol OpenAPIControllerMetadata {
  static var openAPIRoutes: [OpenAPIRouteDescriptor] { get }
}

private struct RouteIdentity: Hashable {
  let method: String
  let path: [PathComponent]

  init(_ route: Route) {
    method = route.method.rawValue
    path = route.path
  }

  init(_ descriptor: OpenAPIRouteDescriptor) throws {
    method = descriptor.method
    // Validate before invoking RoutingKit's string-literal parser, which can trap on malformed braces.
    for segment in descriptor.path {
      guard !segment.isEmpty, !segment.contains("/"), !segment.contains("{"),
        !segment.contains("}"), segment != "*", segment != "**",
        segment != ":", !segment.contains("?"), !segment.contains("#")
      else { throw OpenAPIContractError("Unsupported path segment '\(segment)'.") }
    }
    path = descriptor.path.map { PathComponent(stringLiteral: $0) }
  }
}

private final class RecordingRoutes: RoutesBuilder {
  var routes: [Route] = []

  func add(_ route: Route) {
    routes.append(route)
  }
}

private struct CapturePrefix: Hashable {
  let method: String
  let components: [PathComponent]
}

/// Configuration-time registry. Keep one per application and finish registration before starting it.
/// Registration is staged: native groups/middleware run against a recording root, then final routes
/// and descriptors are validated together before anything is added to the application.
public final class OpenAPIRegistry {
  private let application: Application
  private let info: Info
  private let securitySchemes: [SecurityScheme]
  private var descriptors: [OpenAPIRouteDescriptor] = []
  private var isRegistering = false

  public init(
    application: Application, info: Info, securitySchemes: [SecurityScheme] = []
  ) {
    self.application = application
    self.info = info
    self.securitySchemes = securitySchemes
  }

  public func register<C: RouteCollection & OpenAPIControllerMetadata>(
    _ controller: C, at prefix: [String] = []
  ) async throws {
    // Prefixes are literal groups; typed group captures belong in the manual registration API.
    guard prefix.allSatisfy({ !$0.isEmpty && !$0.contains(where: { "/:*{}?#".contains($0) }) })
    else { throw OpenAPIContractError("Controller prefixes must be literal path segments.") }
    try await register(descriptors: C.openAPIRoutes.map { $0.prefixed(prefix) }) { root in
      try await root.grouped(prefix.map { .constant($0) }).register(collection: controller)
    }
  }

  public func register(
    descriptors newDescriptors: [OpenAPIRouteDescriptor],
    configure: (any RoutesBuilder) async throws -> Void
  ) async throws {
    try validateRoutingMode()
    guard !isRegistering else {
      throw OpenAPIContractError("Registry registration is not reentrant; configure sequentially.")
    }
    isRegistering = true
    defer { isRegistering = false }
    let recorder = RecordingRoutes()
    try await configure(recorder)
    let candidate = descriptors + newDescriptors
    // A descriptor must match this transaction, not a coincidentally matching earlier route.
    let recorded = Set(recorder.routes.map(RouteIdentity.init))
    for descriptor in newDescriptors {
      guard recorded.contains(try RouteIdentity(descriptor)) else {
        throw OpenAPIContractError("No registered route matches operation '\(descriptor.operationID)'.")
      }
    }
    _ = try buildDocument(descriptors: candidate, routes: application.routes.all + recorder.routes)
    for route in recorder.routes { application.add(route) }
    descriptors = candidate
  }

  public func document() throws -> OpenAPIJSONDocument {
    try buildDocument(descriptors: descriptors, routes: application.routes.all)
  }

  public func encodeCanonicalJSON() throws -> Data {
    var data = try document().encodeJSON(prettyPrinted: true)
    data.append(UInt8(ascii: "\n"))
    return data
  }

  private func buildDocument(
    descriptors: [OpenAPIRouteDescriptor], routes: [Route]
  ) throws -> OpenAPIJSONDocument {
    try validateRoutingMode()
    var captureNames: [CapturePrefix: String] = [:]
    for route in routes {
      var prefix: [PathComponent] = []
      for component in route.path {
        if case .parameter(let name) = component {
          // Named parameters and `*` share the native trie's wildcard branch.
          prefix.append(.anything)
          let key = CapturePrefix(method: route.method.rawValue, components: prefix)
          if let previous = captureNames[key], previous != name {
            throw OpenAPIContractError(
              "Shared route prefix has conflicting capture names '\(previous)' and '\(name)'."
            )
          }
          captureNames[key] = name
        } else {
          prefix.append(component)
        }
      }
    }
    let registered = Dictionary(grouping: routes, by: RouteIdentity.init)
    var ids = Set<String>()
    var identities = Set<RouteIdentity>()
    var components: [String: JSONValue] = [:]
    var paths: [(String, OpenAPISchema.Operation, OpenAPIRouteDescriptor)] = []
    let schemeNames = securitySchemes.map(\.name)
    guard Set(schemeNames).count == schemeNames.count else {
      throw OpenAPIContractError("Duplicate security scheme name.")
    }

    for descriptor in descriptors.sorted(by: {
      ($0.path.joined(separator: "/"), $0.method) < ($1.path.joined(separator: "/"), $1.method)
    }) {
      let identity = try RouteIdentity(descriptor)
      guard let method = OpenAPISchema.HTTPMethod(rawValue: descriptor.method.lowercased()),
        descriptor.method == descriptor.method.uppercased()
      else { throw OpenAPIContractError("Unsupported HTTP method '\(descriptor.method)'.") }
      guard !descriptor.operationID.isEmpty, ids.insert(descriptor.operationID).inserted else {
        throw OpenAPIContractError("Empty or duplicate operationID '\(descriptor.operationID)'.")
      }
      guard identities.insert(identity).inserted else {
        throw OpenAPIContractError("Duplicate documented route '\(descriptor.path)'.")
      }
      guard let matches = registered[identity], matches.count == 1 else {
        throw OpenAPIContractError("Operation '\(descriptor.operationID)' needs exactly one registered route.")
      }
      // Equivalent templated paths with different capture names compete for the same native route.
      let shape = identity.path.map { if case .parameter = $0 { ":" } else { $0.description } }
      guard routes.filter({ route in
        route.method.rawValue == identity.method &&
          route.path.map { if case .parameter = $0 { ":" } else { $0.description } } == shape
      }).count == 1 else {
        throw OpenAPIContractError("Ambiguous native route for '\(descriptor.operationID)'.")
      }
      if let scheme = descriptor.security.name, !schemeNames.contains(scheme) {
        throw OpenAPIContractError("Undeclared security scheme '\(scheme)'.")
      }
      let captures = identity.path.compactMap { component -> String? in
        if case .parameter(let name) = component { name } else { nil }
      }
      guard Set(captures).count == captures.count else {
        throw OpenAPIContractError("Duplicate path capture in '\(descriptor.operationID)'.")
      }
      var parameterIDs = Set<String>()
      for parameter in descriptor.parameters {
        let name = parameter.location == .header ? parameter.name.lowercased() : parameter.name
        guard !name.isEmpty, parameterIDs.insert("\(parameter.location.rawValue):\(name)").inserted else {
          throw OpenAPIContractError("Duplicate or empty parameter '\(parameter.name)' in \(parameter.location).")
        }
        if parameter.location == .path {
          guard parameter.required, captures.contains(parameter.name) else {
            throw OpenAPIContractError("Path parameter '\(parameter.name)' must be required and match a capture.")
          }
        }
        if parameter.location == .header,
          ["content-type", "accept", "authorization"].contains(name)
        {
          throw OpenAPIContractError("Use body/response/security contracts for reserved header '\(name)'.")
        }
      }
      var parameters = descriptor.parameters
      for capture in captures where !parameters.contains(where: { $0.location == .path && $0.name == capture }) {
        parameters.append(.path(capture, String.self))
      }
      parameters.sort { ($0.location.rawValue, $0.name) < ($1.location.rawValue, $1.name) }
      var statuses = Set<Int>()
      guard !descriptor.responses.isEmpty else {
        throw OpenAPIContractError("Operation '\(descriptor.operationID)' needs explicit responses.")
      }
      for response in descriptor.responses {
        guard (200...599).contains(response.status), statuses.insert(response.status).inserted,
          !(response.body != nil && [204, 205, 304].contains(response.status)),
          !(descriptor.method == "HEAD" && response.body != nil)
        else { throw OpenAPIContractError("Invalid, duplicate, or bodyless response status \(response.status).") }
      }
      let schemas = [descriptor.requestBody?.component].compactMap { $0 }
        + descriptor.responses.compactMap(\.component)
      for component in schemas {
        guard !component.name.isEmpty,
          component.name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) })
        else { throw OpenAPIContractError("Invalid component name '\(component.name)'.") }
        if let previous = components[component.name], previous != component.value {
          throw OpenAPIContractError("Conflicting schemas for component '\(component.name)'.")
        }
        components[component.name] = component.value
      }
      let path = "/" + identity.path.map { component in
        if case .parameter(let name) = component { "{\(name)}" } else { component.description }
      }.joined(separator: "/")
      let operation = OpenAPISchema.Operation(method: method, operationID: descriptor.operationID) {
        for parameter in parameters {
          Parameter(
            parameter.name, in: parameter.location, schema: parameter.schema, required: parameter.required
          )
        }
        if let request = descriptor.requestBody {
          OpenAPISchema.Request { request.body }
        }
        for response in descriptor.responses.sorted(by: { $0.status < $1.status }) {
          OpenAPISchema.Response(
            .init(rawValue: String(response.status)), description: response.description
          ) {
            if let body = response.body { body }
          }
        }
      }
      paths.append((path, operation, descriptor))
    }
    let document = OpenAPIDocument {
      info
      Components {
        for name in components.keys.sorted() {
          if let value = components[name] { Schema(name, raw: value) }
        }
        for scheme in securitySchemes.sorted(by: { $0.name < $1.name }) { scheme }
      }
      for (path, operation, _) in paths {
        Path(path) { operation }
      }
    }
    // The builder does not yet expose anonymous security alternatives or requestBody.required.
    // Add only those standard fields through the library's lossless JSON document API.
    guard var root = try document.jsonValue().object, var pathObject = root["paths"]?.object else {
      throw OpenAPIContractError("OpenAPI builder did not produce a paths object.")
    }
    for (path, operation, descriptor) in paths {
      guard var item = pathObject[path]?.object,
        var value = item[operation.method.rawValue]?.object
      else { throw OpenAPIContractError("OpenAPI builder omitted '\(descriptor.operationID)'.") }
      switch descriptor.security {
      case .publicAccess:
        value["security"] = .array([])
      case .required(let scheme):
        value["security"] = .array([.object([scheme: .array([])])])
      case .optional(let scheme):
        value["security"] = .array([.object([:]), .object([scheme: .array([])])])
      }
      if let body = descriptor.requestBody {
        guard var request = value["requestBody"]?.object else {
          throw OpenAPIContractError("OpenAPI builder omitted request body.")
        }
        request["required"] = .boolean(body.required)
        value["requestBody"] = .object(request)
      }
      item[operation.method.rawValue] = .object(value)
      pathObject[path] = .object(item)
    }
    root["paths"] = .object(pathObject)
    let result = try OpenAPIJSONDocument(rawValue: .object(root))
    try OpenAPIValidator.assertValid(result)
    return result
  }

  private func validateRoutingMode() throws {
    guard !application.routes.caseInsensitive else {
      throw OpenAPIContractError("Case-insensitive routing is not supported by this OpenAPI prototype.")
    }
  }
}