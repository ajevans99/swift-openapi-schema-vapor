import Foundation
import OpenAPISchema
import OrderedCollections
import OrderedJSON
import Vapor

/// Builds OpenAPI documents from documented routes.
///
/// `documentJSON` is the complete document. The core `OpenAPIDocument` returned by
/// `document` cannot yet express operation extensions, explicit security, response
/// headers, request body requiredness, or request body descriptions; those are applied
/// to the JSON representation, which is then validated against the OpenAPI 3.1
/// meta-schema.
public final class OpenAPIConfiguration {
  private let application: Application

  init(application: Application) {
    self.application = application
  }

  public var info: Info {
    get {
      application.storage[InfoKey.self] ?? Info(title: "Vapor API", version: "1.0.0")
    }
    set {
      application.storage[InfoKey.self] = newValue
    }
  }

  public var servers: [OpenAPISchema.Server] {
    get {
      application.storage[ServersKey.self] ?? []
    }
    set {
      application.storage[ServersKey.self] = newValue
    }
  }

  /// Security schemes emitted under `components.securitySchemes`. Operation security
  /// requirements may only reference these names.
  public var securitySchemes: [SecurityScheme] {
    get {
      application.storage[SecuritySchemesKey.self] ?? []
    }
    set {
      application.storage[SecuritySchemesKey.self] = newValue
    }
  }

  /// Registered routes without `documented(...)` metadata, in registration order.
  public func undocumentedRoutes() -> [Route] {
    application.routes.all.filter { $0.openAPIDocumentation == nil }
  }

  // MARK: Core documents

  public func document() throws -> OpenAPIDocument {
    try document(info: info, servers: servers)
  }

  public func document(
    info: Info,
    servers: [OpenAPISchema.Server] = []
  ) throws -> OpenAPIDocument {
    try assemble(info: info, servers: servers, include: { _ in true }, prefix: [], securitySchemes: nil)
      .document
  }

  /// A document for the documented routes beneath `prefix`, with `prefix` removed from
  /// each path. `servers` defaults to the prefix, so paths stay resolvable.
  public func document(
    info: Info,
    servers: [OpenAPISchema.Server]? = nil,
    including prefix: [PathComponent],
    securitySchemes: [SecurityScheme]? = nil
  ) throws -> OpenAPIDocument {
    try assemble(
      info: info,
      servers: servers ?? [OpenAPISchema.Server(openAPIPath(from: prefix))],
      include: { $0.path.starts(with: prefix, by: samePathComponent) },
      prefix: prefix,
      securitySchemes: securitySchemes
    ).document
  }

  /// A document for the documented routes selected by `include`, with `prefix` removed from
  /// each path. Throws if a selected route does not start with `prefix`. `servers` defaults to
  /// the prefix.
  public func document(
    info: Info,
    servers: [OpenAPISchema.Server]? = nil,
    including include: (Route) -> Bool,
    stripping prefix: [PathComponent],
    securitySchemes: [SecurityScheme]? = nil
  ) throws -> OpenAPIDocument {
    try assemble(
      info: info,
      servers: servers ?? [OpenAPISchema.Server(openAPIPath(from: prefix))],
      include: include,
      prefix: prefix,
      securitySchemes: securitySchemes
    ).document
  }

  // MARK: Complete JSON documents

  public func documentJSON() throws -> JSONValue {
    try documentJSON(info: info, servers: servers)
  }

  public func documentJSON(
    info: Info,
    servers: [OpenAPISchema.Server] = []
  ) throws -> JSONValue {
    try assemble(info: info, servers: servers, include: { _ in true }, prefix: [], securitySchemes: nil)
      .json
  }

  /// The complete JSON document for the documented routes beneath `prefix`, with `prefix`
  /// removed from each path. `servers` defaults to the prefix.
  public func documentJSON(
    info: Info,
    servers: [OpenAPISchema.Server]? = nil,
    including prefix: [PathComponent],
    securitySchemes: [SecurityScheme]? = nil
  ) throws -> JSONValue {
    try assemble(
      info: info,
      servers: servers ?? [OpenAPISchema.Server(openAPIPath(from: prefix))],
      include: { $0.path.starts(with: prefix, by: samePathComponent) },
      prefix: prefix,
      securitySchemes: securitySchemes
    ).json
  }

  /// The complete JSON document for the documented routes selected by `include`, with `prefix`
  /// removed from each path. `servers` defaults to the prefix.
  public func documentJSON(
    info: Info,
    servers: [OpenAPISchema.Server]? = nil,
    including include: (Route) -> Bool,
    stripping prefix: [PathComponent],
    securitySchemes: [SecurityScheme]? = nil
  ) throws -> JSONValue {
    try assemble(
      info: info,
      servers: servers ?? [OpenAPISchema.Server(openAPIPath(from: prefix))],
      include: include,
      prefix: prefix,
      securitySchemes: securitySchemes
    ).json
  }

  @discardableResult
  public func serveJSON(at path: PathComponent...) -> Route {
    serveJSON(at: path)
  }

  @discardableResult
  public func serveJSON(at path: [PathComponent]) -> Route {
    application.get(path) { request throws -> Vapor.Response in
      let data = try OpenAPICanonicalJSON.encode(request.application.openAPI.documentJSON())
      var headers = HTTPHeaders()
      headers.contentType = .json
      return Vapor.Response(status: .ok, headers: headers, body: .init(data: data))
    }
  }

  private func assemble(
    info: Info,
    servers: [OpenAPISchema.Server],
    include: (Route) -> Bool,
    prefix: [PathComponent],
    securitySchemes: [SecurityScheme]?
  ) throws -> (document: OpenAPIDocument, json: JSONValue) {
    for component in prefix {
      guard case .constant = component else {
        throw OpenAPISchemaVaporError.nonConstantPrefix(prefix: openAPIPath(from: prefix))
      }
    }
    let securitySchemes = securitySchemes ?? self.securitySchemes
    var schemeNames = Set<String>()
    for scheme in securitySchemes where !schemeNames.insert(scheme.name).inserted {
      throw OpenAPISchemaVaporError.duplicateSecurityScheme(name: scheme.name)
    }

    var routes: [PreparedRoute] = []
    for route in application.routes.all {
      guard let documentation = route.openAPIDocumentation, include(route) else {
        continue
      }
      routes.append(
        try PreparedRoute(
          route: route,
          documentation: documentation,
          prefix: prefix,
          securitySchemeNames: schemeNames
        )
      )
    }

    let schemas = try uniqueSchemas(from: routes.flatMap { $0.documentation.schemas })
    let groupedRoutes = Dictionary(grouping: routes, by: \.path).sorted { $0.key < $1.key }

    let document = OpenAPIDocument {
      info

      for server in servers {
        server
      }

      if !schemas.isEmpty || !securitySchemes.isEmpty {
        Components {
          for schema in schemas {
            schema
          }
          for scheme in securitySchemes {
            scheme
          }
        }
      }

      for (path, pathRoutes) in groupedRoutes {
        Path(path) {
          for route in pathRoutes.sorted(by: routeSort) {
            route.operation()
          }
        }
      }
    }

    let json = patched(try document.jsonValue(), with: routes)
    try OpenAPIValidator.assertValid(OpenAPIJSONDocument(rawValue: json))
    return (document, json)
  }
}

/// Pretty-printed JSON with a trailing newline, matching `OpenAPIDocument.encodeCanonicalJSON`.
public enum OpenAPICanonicalJSON {
  public static func encode(_ value: JSONValue, prettyPrinted: Bool = true) throws -> Data {
    var data = try value.serializedData(
      options: JSONValue.SerializationOptions(prettyPrinted: prettyPrinted))
    if data.last != UInt8(ascii: "\n") {
      data.append(UInt8(ascii: "\n"))
    }
    return data
  }
}

private struct InfoKey: StorageKey {
  typealias Value = Info
}

private struct ServersKey: StorageKey {
  typealias Value = [OpenAPISchema.Server]
}

private struct SecuritySchemesKey: StorageKey {
  typealias Value = [SecurityScheme]
}

private struct PreparedRoute {
  let route: Route
  let documentation: OpenAPIRouteDocumentation
  let method: OpenAPISchema.HTTPMethod
  /// The OpenAPI path relative to the document prefix.
  let path: String
  /// Route parameters without documented `.path` metadata, in path order.
  let automaticPathParameters: [String]

  init(
    route: Route,
    documentation: OpenAPIRouteDocumentation,
    prefix: [PathComponent],
    securitySchemeNames: Set<String>
  ) throws {
    let operationID = documentation.operationID
    let fullPath = openAPIPath(from: route.path)
    guard route.path.starts(with: prefix, by: samePathComponent) else {
      throw OpenAPISchemaVaporError.routeOutsidePrefix(
        operationID: operationID, path: fullPath, prefix: openAPIPath(from: prefix))
    }
    self.route = route
    self.documentation = documentation
    for component in route.path {
      switch component {
      case .anything, .catchall:
        throw OpenAPISchemaVaporError.unsupportedPathComponent(
          operationID: operationID, path: fullPath, component: "\(component)")
      case .constant, .parameter:
        continue
      }
    }
    let relativeComponents = Array(route.path.dropFirst(prefix.count))
    self.path = openAPIPath(from: relativeComponents)
    self.method = try openAPIMethod(from: route.method, path: fullPath)

    var parameterKeys = Set<String>()
    for parameter in documentation.parameters
    where !parameterKeys.insert("\(parameter.location.rawValue)\u{0}\(parameter.name)").inserted {
      throw OpenAPISchemaVaporError.duplicateParameter(
        operationID: operationID, name: parameter.name, location: parameter.location.rawValue)
    }

    let routeParameterNames = relativeComponents.compactMap { component -> String? in
      guard case .parameter(let name) = component else { return nil }
      return name
    }
    let documentedPathNames = Set(
      documentation.parameters.filter { $0.location == .path }.map(\.name))
    for name in documentedPathNames.sorted() where !routeParameterNames.contains(name) {
      throw OpenAPISchemaVaporError.unknownPathParameter(
        operationID: operationID, path: fullPath, name: name)
    }
    self.automaticPathParameters = routeParameterNames.filter { !documentedPathNames.contains($0) }

    if let security = documentation.security {
      if case .required(let alternatives) = security, alternatives.isEmpty {
        throw OpenAPISchemaVaporError.emptySecurityRequirement(operationID: operationID)
      }
      for name in security.schemeNames.sorted() where !securitySchemeNames.contains(name) {
        throw OpenAPISchemaVaporError.unknownSecurityScheme(operationID: operationID, scheme: name)
      }
    }

    for key in documentation.extensions.keys.sorted()
    where !key.hasPrefix("x-") || key.hasPrefix("x-oai-") || key.hasPrefix("x-oas-") {
      throw OpenAPISchemaVaporError.invalidExtensionKey(operationID: operationID, key: key)
    }
  }

  func operation() -> OpenAPISchema.Operation {
    let documentation = documentation
    let automaticPathParameters = automaticPathParameters
    return OpenAPISchema.Operation(method: method, operationID: documentation.operationID) {
      for tag in documentation.tags {
        Tags(tag)
      }

      if let summary = documentation.summary {
        Summary(summary)
      }

      if let description = documentation.description {
        Description(description)
      }

      for name in automaticPathParameters {
        OpenAPISchema.PathParameter(name)
      }

      for parameter in documentation.parameters {
        parameter.parameter()
      }

      if let requestBody = documentation.requestBody {
        Request {
          for body in requestBody.bodies {
            body
          }
        }
      }

      for response in documentation.responses {
        OpenAPISchema.Response(
          openAPIStatus(from: response.status),
          description: response.description
        ) {
          for body in response.bodies {
            body
          }
        }
      }
    }
  }

  /// Applies the fields the core `Operation` cannot emit yet.
  func patch(_ operation: inout OrderedDictionary<String, JSONValue>) {
    if let requestBody = documentation.requestBody,
      case .object(let body)? = operation["requestBody"]
    {
      var rebuilt: OrderedDictionary<String, JSONValue> = [:]
      if let description = requestBody.description {
        rebuilt["description"] = .string(description)
      }
      rebuilt["required"] = .boolean(requestBody.required)
      for (key, value) in body where key != "required" && key != "description" {
        rebuilt[key] = value
      }
      operation["requestBody"] = .object(rebuilt)
    }

    if case .object(var responses)? = operation["responses"] {
      for response in documentation.responses where !response.headers.isEmpty {
        let status = String(response.status.code)
        guard case .object(let object)? = responses[status] else { continue }
        var headers: OrderedDictionary<String, JSONValue> = [:]
        for name in response.headers.keys.sorted() {
          headers[name] = response.headers[name]?.jsonValue()
        }
        var rebuilt: OrderedDictionary<String, JSONValue> = [:]
        for (key, value) in object where key != "headers" {
          rebuilt[key] = value
          if key == "description" {
            rebuilt["headers"] = .object(headers)
          }
        }
        responses[status] = .object(rebuilt)
      }
      operation["responses"] = .object(responses)
    }

    if let security = documentation.security {
      operation["security"] = security.jsonValue()
    }

    for key in documentation.extensions.keys.sorted() {
      operation[key] = documentation.extensions[key]
    }
  }
}

private func patched(_ json: JSONValue, with routes: [PreparedRoute]) -> JSONValue {
  guard case .object(var root) = json, case .object(var paths)? = root["paths"] else {
    return json
  }
  for route in routes {
    let method = route.method.rawValue
    guard case .object(var item)? = paths[route.path],
      case .object(var operation)? = item[method]
    else { continue }
    route.patch(&operation)
    item[method] = .object(operation)
    paths[route.path] = .object(item)
  }
  root["paths"] = .object(paths)
  return .object(root)
}

private func uniqueSchemas(from schemas: [OpenAPISchema.Schema]) throws -> [OpenAPISchema.Schema] {
  var seen: [String: JSONValue] = [:]
  var unique: [OpenAPISchema.Schema] = []
  for schema in schemas {
    let value = try componentJSON(schema)
    if let existing = seen[schema.name] {
      guard existing == value else {
        throw OpenAPISchemaVaporError.conflictingComponentSchema(name: schema.name)
      }
      continue
    }
    seen[schema.name] = value
    unique.append(schema)
  }
  return unique.sorted { $0.name < $1.name }
}

/// The component's JSON Schema, read through the core's public document API.
private func componentJSON(_ schema: OpenAPISchema.Schema) throws -> JSONValue {
  let document = OpenAPIDocument {
    Info(title: "component", version: "0")
    Components {
      schema
    }
  }
  return try document.jsonValue().object?["components"]?.object?["schemas"]?.object?[schema.name]
    ?? .null
}

private func samePathComponent(_ lhs: PathComponent, _ rhs: PathComponent) -> Bool {
  lhs.description == rhs.description
}

private func openAPIPath(from components: [PathComponent]) -> String {
  let path = components.map(openAPIPathSegment).joined(separator: "/")
  return path.isEmpty ? "/" : "/" + path
}

private func openAPIPathSegment(from component: PathComponent) -> String {
  let rawValue = "\(component)"
  if rawValue.hasPrefix(":") {
    return "{\(rawValue.dropFirst())}"
  }
  return rawValue
}

private func routeSort(_ lhs: PreparedRoute, _ rhs: PreparedRoute) -> Bool {
  lhs.route.method.rawValue < rhs.route.method.rawValue
}

private func openAPIMethod(
  from method: Vapor.HTTPMethod,
  path: String
) throws -> OpenAPISchema.HTTPMethod {
  switch method {
  case .GET: .get
  case .PUT: .put
  case .POST: .post
  case .DELETE: .delete
  case .PATCH: .patch
  case .HEAD: .head
  case .OPTIONS: .options
  case .TRACE: .trace
  default:
    throw OpenAPISchemaVaporError.unsupportedHTTPMethod(method: method.rawValue, path: path)
  }
}

private func openAPIStatus(from status: Vapor.HTTPStatus) -> OpenAPISchema.HTTPStatus {
  OpenAPISchema.HTTPStatus(rawValue: String(status.code))
}
