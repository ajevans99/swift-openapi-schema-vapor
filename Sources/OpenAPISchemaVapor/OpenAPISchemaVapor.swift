import JSONSchemaBuilder
import OpenAPISchema
import OrderedCollections
import OrderedJSON
import Vapor

public struct OpenAPIRequestBodyDocumentation: Sendable {
  /// Media types accepted by the operation, in declaration order.
  public let bodies: [Body]
  public let schemas: [OpenAPISchema.Schema]
  /// Emitted as `requestBody.required`. Defaults to `true`.
  public let required: Bool
  public let description: String?

  /// The first declared media type.
  public var body: Body { bodies[0] }

  public init(
    body: Body,
    schemas: [OpenAPISchema.Schema] = [],
    required: Bool = true,
    description: String? = nil
  ) {
    self.init(bodies: [body], schemas: schemas, required: required, description: description)
  }

  public init(
    bodies: [Body],
    schemas: [OpenAPISchema.Schema] = [],
    required: Bool = true,
    description: String? = nil
  ) {
    precondition(!bodies.isEmpty, "A request body needs at least one media type.")
    self.bodies = bodies
    self.schemas = schemas
    self.required = required
    self.description = description
  }

  /// A body with any media type, for example `application/octet-stream` or
  /// `application/x-www-form-urlencoded`.
  public init(
    mediaType: MediaType,
    schema: OpenAPISchemaValue,
    schemas: [OpenAPISchema.Schema] = [],
    required: Bool = true,
    description: String? = nil
  ) {
    self.init(
      body: Body(mediaType, schema: schema),
      schemas: schemas,
      required: required,
      description: description
    )
  }

  @available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
  public static func json<T: Content & Schemable>(
    _ type: T.Type,
    name: String? = nil,
    required: Bool = true,
    description: String? = nil
  ) -> Self {
    Self(
      body: JSONBody(type, name: name),
      schemas: [OpenAPISchema.Schema(type, name: name)],
      required: required,
      description: description
    )
  }

  /// A JSON body described by a schema value, for types that are not `Schemable`.
  /// Register named components referenced by `schema` in `schemas`.
  public static func json(
    schema: OpenAPISchemaValue,
    schemas: [OpenAPISchema.Schema] = [],
    required: Bool = true,
    description: String? = nil
  ) -> Self {
    Self(
      mediaType: .json,
      schema: schema,
      schemas: schemas,
      required: required,
      description: description
    )
  }
}

/// An OpenAPI Header Object attached to a documented response.
public struct OpenAPIHeaderDocumentation: Sendable {
  public let schema: OpenAPISchemaValue
  public let description: String?
  public let required: Bool

  public init(
    schema: OpenAPISchemaValue = .string(),
    description: String? = nil,
    required: Bool = false
  ) {
    self.schema = schema
    self.description = description
    self.required = required
  }

  func jsonValue() -> JSONValue {
    var object: OrderedDictionary<String, JSONValue> = [:]
    if let description {
      object["description"] = .string(description)
    }
    if required {
      object["required"] = .boolean(true)
    }
    object["schema"] = schema.jsonValue()
    return .object(object)
  }
}

public struct OpenAPIResponseDocumentation: Sendable {
  public let status: Vapor.HTTPStatus
  public let description: String?
  /// Response media types, in declaration order.
  public let bodies: [Body]
  public let schemas: [OpenAPISchema.Schema]
  public let headers: [String: OpenAPIHeaderDocumentation]

  /// The first declared media type, if any.
  public var body: Body? { bodies.first }

  public init(
    status: Vapor.HTTPStatus,
    description: String? = nil,
    body: Body? = nil,
    schemas: [OpenAPISchema.Schema] = [],
    headers: [String: OpenAPIHeaderDocumentation] = [:]
  ) {
    self.init(
      status: status,
      description: description,
      bodies: body.map { [$0] } ?? [],
      schemas: schemas,
      headers: headers
    )
  }

  public init(
    status: Vapor.HTTPStatus,
    description: String? = nil,
    bodies: [Body],
    schemas: [OpenAPISchema.Schema] = [],
    headers: [String: OpenAPIHeaderDocumentation] = [:]
  ) {
    self.status = status
    self.description = description
    self.bodies = bodies
    self.schemas = schemas
    self.headers = headers
  }

  /// A response with any media type, for example `text/event-stream` or `text/csv`.
  public init(
    _ status: Vapor.HTTPStatus,
    mediaType: MediaType,
    schema: OpenAPISchemaValue,
    description: String? = nil,
    schemas: [OpenAPISchema.Schema] = [],
    headers: [String: OpenAPIHeaderDocumentation] = [:]
  ) {
    self.init(
      status: status,
      description: description,
      bodies: [Body(mediaType, schema: schema)],
      schemas: schemas,
      headers: headers
    )
  }

  public static func empty(
    _ status: Vapor.HTTPStatus,
    description: String? = nil,
    headers: [String: OpenAPIHeaderDocumentation] = [:]
  ) -> Self {
    Self(status: status, description: description, headers: headers)
  }

  @available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
  public static func json<T: ResponseEncodable & Schemable>(
    _ status: Vapor.HTTPStatus,
    _ type: T.Type,
    name: String? = nil,
    description: String? = nil,
    headers: [String: OpenAPIHeaderDocumentation] = [:]
  ) -> Self {
    Self(
      status: status,
      description: description,
      body: JSONBody(type, name: name),
      schemas: [OpenAPISchema.Schema(type, name: name)],
      headers: headers
    )
  }

  /// A JSON response described by a schema value, for types that are not `Schemable`.
  /// Register named components referenced by `schema` in `schemas`.
  public static func json(
    _ status: Vapor.HTTPStatus,
    schema: OpenAPISchemaValue,
    schemas: [OpenAPISchema.Schema] = [],
    description: String? = nil,
    headers: [String: OpenAPIHeaderDocumentation] = [:]
  ) -> Self {
    Self(
      status,
      mediaType: .json,
      schema: schema,
      description: description,
      schemas: schemas,
      headers: headers
    )
  }
}

extension OpenAPISchema.Schema {
  /// A named component schema written as raw JSON Schema, for types that are not `Schemable`.
  public static func component(_ name: String, raw: JSONValue) -> Self {
    Self(name, raw: raw)
  }
}

/// Operation security. `nil` on a route inherits the document's top-level security.
public enum OpenAPISecurityDocumentation: Sendable, Equatable {
  /// Alternative requirements; each maps security scheme names to required scopes.
  /// All schemes within one requirement apply together.
  case required([[String: [String]]])
  /// No credentials; emitted as `security: []`.
  case anonymous

  public static func scheme(_ name: String, scopes: [String] = []) -> Self {
    .required([[name: scopes]])
  }

  var schemeNames: Set<String> {
    switch self {
    case .anonymous: []
    case .required(let alternatives): Set(alternatives.flatMap(\.keys))
    }
  }

  func jsonValue() -> JSONValue {
    switch self {
    case .anonymous:
      return .array([])
    case .required(let alternatives):
      return .array(
        alternatives.map { requirement in
          var object: OrderedDictionary<String, JSONValue> = [:]
          for name in requirement.keys.sorted() {
            object[name] = .array((requirement[name] ?? []).map(JSONValue.string))
          }
          return .object(object)
        })
    }
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

// swift-format-ignore: AlwaysUseLowerCamelCase
public func PathParameter(
  _ name: String,
  schema: OpenAPISchemaValue = .string(),
  description: String? = nil
) -> OpenAPIParameterDocumentation {
  OpenAPIParameterDocumentation(name, in: .path, schema: schema, required: true, description: description)
}

// swift-format-ignore: AlwaysUseLowerCamelCase
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

// swift-format-ignore: AlwaysUseLowerCamelCase
public func HeaderParameter(
  _ name: String,
  schema: OpenAPISchemaValue = .string(),
  required: Bool = false,
  description: String? = nil
) -> OpenAPIParameterDocumentation {
  OpenAPIParameterDocumentation(
    name,
    in: .header,
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
  /// `nil` inherits the document's top-level security.
  public let security: OpenAPISecurityDocumentation?
  /// Specification extensions; every key must start with `x-`.
  public let extensions: [String: JSONValue]

  public init(
    operationID: String,
    tags: [String] = [],
    summary: String? = nil,
    description: String? = nil,
    parameters: [OpenAPIParameterDocumentation] = [],
    requestBody: OpenAPIRequestBodyDocumentation? = nil,
    responses: [OpenAPIResponseDocumentation],
    security: OpenAPISecurityDocumentation? = nil,
    extensions: [String: JSONValue] = [:]
  ) {
    self.operationID = operationID
    self.tags = tags
    self.summary = summary
    self.description = description
    self.parameters = parameters
    self.requestBody = requestBody
    self.responses = responses
    self.security = security
    self.extensions = extensions
  }

  var schemas: [OpenAPISchema.Schema] {
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
    responses: [OpenAPIResponseDocumentation],
    security: OpenAPISecurityDocumentation? = nil,
    extensions: [String: JSONValue] = [:]
  ) -> Self {
    documented(
      OpenAPIRouteDocumentation(
        operationID: operationID,
        tags: tags,
        summary: summary,
        description: description,
        parameters: parameters,
        requestBody: requestBody,
        responses: responses,
        security: security,
        extensions: extensions
      )
    )
  }
}

extension Application {
  public var openAPI: OpenAPIConfiguration {
    OpenAPIConfiguration(application: self)
  }
}
