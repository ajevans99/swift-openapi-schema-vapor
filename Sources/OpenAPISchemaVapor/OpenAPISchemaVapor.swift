import JSONSchemaBuilder
import OpenAPISchema
import Vapor

public struct OpenAPIRequestBodyDocumentation: Sendable {
  public let body: Body
  public let schemas: [Schema]

  public init(body: Body, schemas: [Schema] = []) {
    self.body = body
    self.schemas = schemas
  }

  @available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
  public static func json<T: Content & Schemable>(
    _ type: T.Type,
    name: String? = nil
  ) -> Self {
    Self(body: JSONBody(type, name: name), schemas: [Schema(type, name: name)])
  }
}

public struct OpenAPIResponseDocumentation: Sendable {
  public let status: Vapor.HTTPStatus
  public let description: String?
  public let body: Body?
  public let schemas: [Schema]

  public init(
    status: Vapor.HTTPStatus,
    description: String? = nil,
    body: Body? = nil,
    schemas: [Schema] = []
  ) {
    self.status = status
    self.description = description
    self.body = body
    self.schemas = schemas
  }

  public static func empty(
    _ status: Vapor.HTTPStatus,
    description: String? = nil
  ) -> Self {
    Self(status: status, description: description)
  }

  @available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
  public static func json<T: ResponseEncodable & Schemable>(
    _ status: Vapor.HTTPStatus,
    _ type: T.Type,
    name: String? = nil,
    description: String? = nil
  ) -> Self {
    Self(
      status: status,
      description: description,
      body: JSONBody(type, name: name),
      schemas: [Schema(type, name: name)]
    )
  }
}

public struct OpenAPIParameterDocumentation: Sendable {
  public let name: String
  public let location: ParameterLocation
  public let schema: OpenAPISchemaValue
  public let required: Bool
  public let description: String?

  public init(
    _ name: String,
    in location: ParameterLocation,
    schema: OpenAPISchemaValue = .string(),
    required: Bool? = nil,
    description: String? = nil
  ) {
    self.name = name
    self.location = location
    self.schema = schema
    self.required = required ?? (location == .path)
    self.description = description
  }

  func parameter() -> Parameter {
    Parameter(
      name,
      in: location,
      schema: schema,
      required: required,
      description: description
    )
  }
}

public func PathParameter(
  _ name: String,
  schema: OpenAPISchemaValue = .string(),
  description: String? = nil
) -> OpenAPIParameterDocumentation {
  OpenAPIParameterDocumentation(name, in: .path, schema: schema, required: true, description: description)
}

public func QueryParameter(
  _ name: String,
  schema: OpenAPISchemaValue = .string(),
  required: Bool = false,
  description: String? = nil
) -> OpenAPIParameterDocumentation {
  OpenAPIParameterDocumentation(
    name,
    in: .query,
    schema: schema,
    required: required,
    description: description
  )
}

public struct OpenAPIRouteDocumentation: Sendable {
  public let operationID: String
  public let tags: [String]
  public let summary: String?
  public let description: String?
  public let parameters: [OpenAPIParameterDocumentation]
  public let requestBody: OpenAPIRequestBodyDocumentation?
  public let responses: [OpenAPIResponseDocumentation]

  public init(
    operationID: String,
    tags: [String] = [],
    summary: String? = nil,
    description: String? = nil,
    parameters: [OpenAPIParameterDocumentation] = [],
    requestBody: OpenAPIRequestBodyDocumentation? = nil,
    responses: [OpenAPIResponseDocumentation]
  ) {
    self.operationID = operationID
    self.tags = tags
    self.summary = summary
    self.description = description
    self.parameters = parameters
    self.requestBody = requestBody
    self.responses = responses
  }

  var schemas: [Schema] {
    (requestBody?.schemas ?? []) + responses.flatMap(\.schemas)
  }
}

extension Route {
  private static let documentationKey: AnySendableHashable = "openapi-schema-vapor.documentation"

  public var openAPIDocumentation: OpenAPIRouteDocumentation? {
    get {
      userInfo[Self.documentationKey] as? OpenAPIRouteDocumentation
    }
    set {
      userInfo[Self.documentationKey] = newValue
    }
  }

  @discardableResult
  public func documented(_ documentation: OpenAPIRouteDocumentation) -> Self {
    openAPIDocumentation = documentation
    return self
  }

  @discardableResult
  public func documented(
    operationID: String,
    tags: [String] = [],
    summary: String? = nil,
    description: String? = nil,
    parameters: [OpenAPIParameterDocumentation] = [],
    requestBody: OpenAPIRequestBodyDocumentation? = nil,
    responses: [OpenAPIResponseDocumentation]
  ) -> Self {
    documented(
      OpenAPIRouteDocumentation(
        operationID: operationID,
        tags: tags,
        summary: summary,
        description: description,
        parameters: parameters,
        requestBody: requestBody,
        responses: responses
      )
    )
  }
}

extension Application {
  public var openAPI: OpenAPIConfiguration {
    OpenAPIConfiguration(application: self)
  }
}

public final class OpenAPIConfiguration {
  private let application: Application

  fileprivate init(application: Application) {
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

  public func document() throws -> OpenAPIDocument {
    try document(info: info, servers: servers)
  }

  public func document(
    info: Info,
    servers: [OpenAPISchema.Server] = []
  ) throws -> OpenAPIDocument {
    let documentedRoutes = application.routes.all.compactMap { route -> DocumentedRoute? in
      guard let documentation = route.openAPIDocumentation else {
        return nil
      }
      return DocumentedRoute(route: route, documentation: documentation)
    }

    let schemas = uniqueSchemas(from: documentedRoutes.flatMap { $0.documentation.schemas })
    let groupedRoutes = Dictionary(grouping: documentedRoutes, by: { openAPIPath(from: $0.route.path) })
      .sorted { $0.key < $1.key }

    let document = OpenAPIDocument {
      info

      for server in servers {
        server
      }

      if !schemas.isEmpty {
        Components {
          for schema in schemas {
            schema
          }
        }
      }

      for (path, routes) in groupedRoutes {
        Path(path) {
          for route in routes.sorted(by: routeSort) {
            operation(for: route)
          }
        }
      }
    }
    try OpenAPIValidator.assertValid(document)
    return document
  }

  @discardableResult
  public func serveJSON(at path: PathComponent...) -> Route {
    serveJSON(at: path)
  }

  @discardableResult
  public func serveJSON(at path: [PathComponent]) -> Route {
    application.get(path) { request throws -> Vapor.Response in
      let data = try request.application.openAPI.document().encodeCanonicalJSON()
      var headers = HTTPHeaders()
      headers.contentType = .json
      return Vapor.Response(status: .ok, headers: headers, body: .init(data: data))
    }
  }
}

private struct InfoKey: StorageKey {
  typealias Value = Info
}

private struct ServersKey: StorageKey {
  typealias Value = [OpenAPISchema.Server]
}

private struct DocumentedRoute {
  let route: Route
  let documentation: OpenAPIRouteDocumentation
}

private func uniqueSchemas(from schemas: [Schema]) -> [Schema] {
  var seen = Set<String>()
  var unique: [Schema] = []
  for schema in schemas where seen.insert(schema.name).inserted {
    unique.append(schema)
  }
  return unique.sorted { $0.name < $1.name }
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

private func routeSort(_ lhs: DocumentedRoute, _ rhs: DocumentedRoute) -> Bool {
  lhs.route.method.rawValue < rhs.route.method.rawValue
}

private func operation(for documentedRoute: DocumentedRoute) -> OpenAPISchema.Operation {
  let documentation = documentedRoute.documentation
  let method = openAPIMethod(from: documentedRoute.route.method)
  let pathParameterNames = documentedRoute.route.path.compactMap { component -> String? in
    let segment = "\(component)"
    guard segment.hasPrefix(":") else {
      return nil
    }
    return String(segment.dropFirst())
  }
  let documentedParameterNames = Set(documentation.parameters.map(\.name))

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

    for name in pathParameterNames where !documentedParameterNames.contains(name) {
      OpenAPISchema.PathParameter(name)
    }

    for parameter in documentation.parameters {
      parameter.parameter()
    }

    if let requestBody = documentation.requestBody {
      Request {
        requestBody.body
      }
    }

    for response in documentation.responses {
      OpenAPISchema.Response(
        openAPIStatus(from: response.status),
        description: response.description
      ) {
        if let body = response.body {
          body
        }
      }
    }
  }
}

private func openAPIMethod(from method: Vapor.HTTPMethod) -> OpenAPISchema.HTTPMethod {
  switch method {
  case .GET:
    .get
  case .POST:
    .post
  case .PUT:
    .put
  case .PATCH:
    .patch
  case .DELETE:
    .delete
  default:
    .get
  }
}

private func openAPIStatus(from status: Vapor.HTTPStatus) -> OpenAPISchema.HTTPStatus {
  OpenAPISchema.HTTPStatus(rawValue: String(status.code))
}
