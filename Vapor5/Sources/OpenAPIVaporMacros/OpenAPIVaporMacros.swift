public import OpenAPISchemaVapor5

/// Adds documentation metadata to a native Vapor `@Controller`.
///
/// Only methods marked with `@OpenAPIOperation` are documented. Native Vapor macros
/// remain solely responsible for registering routes, extracting arguments, and authentication.
///
/// Supported routes use attached `@GET`, `@POST`, `@PUT`, `@PATCH`, or `@DELETE`,
/// with one plain literal string per segment and unqualified primitive captures:
/// `Int.self`, `String.self`, `Double.self`, `Bool.self`, or `UUID.self`.
/// Path factories require `OpenAPIParameterValue` and `LosslessStringConvertible`.
/// Captures retain native names
/// (`:int0`, `:string1`), regardless of handler parameter labels. Manual capture
/// aliases, wildcards, conditional routes, `@HTTP`, and `on:` forms are unsupported.
/// The generated `openAPIRoutes` member is reserved.
@attached(member, names: named(openAPIRoutes))
@attached(extension, conformances: OpenAPIControllerMetadata)
public macro OpenAPIController() =
  #externalMacro(module: "OpenAPIVaporMacrosPlugin", type: "OpenAPIControllerMacro")

/// Documents the JSON success response of a native route returning `JSONResponse<Model>`.
///
/// The handler must return a response whose status matches this declaration.
/// The default is 200. JSON success statuses must be 200–299, excluding bodyless
/// 204 and 205. Arbitrary `Content`, raw responses, and opaque return types are not inferred.
/// `JSONResponse` requires its model to conform to `Codable`, `Schemable`, and `Sendable`.
@attached(peer)
public macro OpenAPIOperation(_ operationID: String, status: Int = 200) =
  #externalMacro(module: "OpenAPIVaporMacrosPlugin", type: "OpenAPIMarkerMacro")

/// Documents a JSON request body. The handler remains responsible for decoding it.
/// The generated factory requires the type to conform to `Codable` and `Schemable`.
@attached(peer)
public macro OpenAPIRequestBody(_ type: Any.Type) =
  #externalMacro(module: "OpenAPIVaporMacrosPlugin", type: "OpenAPIMarkerMacro")

/// Documents a query parameter, optional by default. The handler remains responsible for decoding it.
/// The generated factory requires `OpenAPIParameterValue`, not `Schemable`.
@attached(peer)
public macro OpenAPIQuery(_ name: String, _ type: Any.Type, required: Bool = false) =
  #externalMacro(module: "OpenAPIVaporMacrosPlugin", type: "OpenAPIMarkerMacro")

/// Documents a header parameter, optional by default. The handler remains responsible for decoding it.
/// The generated factory requires `OpenAPIParameterValue`, not `Schemable`.
@attached(peer)
public macro OpenAPIHeader(_ name: String, _ type: Any.Type, required: Bool = false) =
  #externalMacro(module: "OpenAPIVaporMacrosPlugin", type: "OpenAPIMarkerMacro")

/// Adds a JSON error response declaration without changing error handling.
/// Repeat this marker for distinct statuses in 400–599. The body type must conform
/// to `Codable` and `Schemable`.
@attached(peer)
public macro OpenAPIError(_ status: Int, _ type: Any.Type) =
  #externalMacro(module: "OpenAPIVaporMacrosPlugin", type: "OpenAPIMarkerMacro")

/// Names a security scheme explicitly; no scheme is inferred from an authentication type.
/// This marker is mandatory on documented native `@AuthMiddleware` routes, and
/// `optional` must match the native authentication parameter's optionality.
@attached(peer)
public macro OpenAPISecurity(_ scheme: String, optional: Bool = false) =
  #externalMacro(module: "OpenAPIVaporMacrosPlugin", type: "OpenAPIMarkerMacro")