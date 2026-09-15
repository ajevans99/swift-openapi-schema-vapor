import CustomDump
import Foundation
import JSONSchema
import JSONSchemaBuilder
import struct OpenAPISchema.Info
import enum OpenAPISchema.OpenAPIValidator
import func OpenAPISchema.BearerAuth
import OpenAPISchemaVapor5
import OpenAPIVaporMacros
import Testing
import Vapor
import VaporMacros
import VaporTesting

@Schemable
struct FailureBody: Content, Equatable {
  let error: Bool
  let reason: String
}

struct SessionUser: Authenticatable {
  let name: String
}

struct TokenMiddleware: Middleware {
  func respond(to request: Request, chainingTo next: any Responder) async throws -> Response {
    if request.headers[.authorization] == "Bearer fixture-token" {
      request.auth.login(SessionUser(name: "Authenticated"))
    }
    return try await next.respond(to: request)
  }
}

@OpenAPIController
@Controller
struct DocumentedUsers {
  @GET("users", Int.self)
  @OpenAPIOperation("getUser")
  @OpenAPIQuery("name", String.self)
  @OpenAPIHeader("X-Trace", String.self, required: true)
  @OpenAPIError(400, FailureBody.self)
  @OpenAPIError(404, FailureBody.self)
  @OpenAPIError(422, FailureBody.self)
  func get(req: Request, id: Int) async throws -> JSONResponse<User> {
    guard req.headers[.init("X-Trace")!] != nil else { throw Abort(.badRequest, reason: "X-Trace is required") }
    guard id != 0 else { throw Abort(.notFound, reason: "No user") }
    let name = try req.query.get(String?.self, at: "name")
    return JSONResponse(User(id: id, name: name ?? "Blob"))
  }

  @POST("users")
  @OpenAPIOperation("createUser", status: 201)
  @OpenAPIRequestBody(CreateUser.self)
  @OpenAPIError(400, FailureBody.self)
  func create(req: Request) async throws -> JSONResponse<User> {
    let input = try await req.content.decode(CreateUser.self)
    return JSONResponse(User(id: 42, name: input.name), status: 201)
  }

  @GET("me")
  @AuthMiddleware(SessionUser.self, TokenMiddleware())
  @OpenAPIOperation("currentUser")
  @OpenAPISecurity("bearer")
  @OpenAPIError(401, FailureBody.self)
  func me(req: Request, user: SessionUser) async throws -> JSONResponse<User> {
    JSONResponse(User(id: 1, name: user.name))
  }

  @GET("feed")
  @OpenAPIOperation("feed")
  @OpenAPISecurity("bearer", optional: true)
  @AuthMiddleware(SessionUser.self, TokenMiddleware())
  func feed(req: Request, user: SessionUser?) async throws -> JSONResponse<User> {
    JSONResponse(User(id: 1, name: user?.name ?? "Anonymous"))
  }

  @GET("opaque")
  func opaque(req: Request) async throws -> some ResponseEncodable { "Still native" }
}

@Suite struct MacroIntegrationTests {
  @Test(arguments: [false, true])
  func nativeHTTPAndSpecAgree(live: Bool) async throws {
    try await withApp { app in
      let registry = OpenAPIRegistry(
        application: app, info: Info(title: "Native", version: "1"),
        securitySchemes: [BearerAuth("bearer")]
      )
      try await registry.register(DocumentedUsers(), at: ["api", "v1"])
      let document = try registry.document()
      let spec = document.rawValue
      let get = try #require(spec["paths"]?["/api/v1/users/{int0}"]?["get"])
      expectNoDifference(
        get["parameters"]?.array?.map { $0["name"] }, [.string("X-Trace"), .string("int0"), .string("name")]
      )
      expectNoDifference(get["parameters"]?[1]?["schema"]?["type"], .string("integer"))
      expectNoDifference(get["parameters"]?[1]?["required"], .boolean(true))
      expectNoDifference(get["parameters"]?[2]?["required"], .boolean(false))
      expectNoDifference(spec["paths"]?["/api/v1/opaque"], nil)
      expectNoDifference(spec["components"]?["securitySchemes"]?["bearer"]?["scheme"], .string("bearer"))
      expectNoDifference(spec["paths"]?["/api/v1/me"]?["get"]?["security"], .array([.object(["bearer": .array([])])]))
      expectNoDifference(spec["paths"]?["/api/v1/feed"]?["get"]?["security"], .array([.object([:]), .object(["bearer": .array([])])]))
      try OpenAPIValidator.assertValid(document)
      try await app.testing(live ? .running : .inMemory) { client in
        let user = try await client.get("/api/v1/users/7?name=Alice", headers: [.init("X-Trace")!: "trace"])
        try await assertSuccess(
          user, status: 200, expected: User(id: 7, name: "Alice"), operation: get, spec: spec
        )
        let missingHeader = try await client.get("/api/v1/users/7")
        try await assertError(missingHeader, status: 400, operation: get, spec: spec)
        let invalidPath = try await client.get("/api/v1/users/not-an-int", headers: [.init("X-Trace")!: "trace"])
        try await assertError(invalidPath, status: 422, operation: get, spec: spec)
        let missingUser = try await client.get("/api/v1/users/0", headers: [.init("X-Trace")!: "trace"])
        try await assertError(missingUser, status: 404, operation: get, spec: spec)
        let postOperation = try #require(spec["paths"]?["/api/v1/users"]?["post"])
        let input = try JSONEncoder().encode(CreateUser(name: "Created"))
        let inputSchema = try #require(spec["components"]?["schemas"]?["CreateUser"])
        let requestSchema = try Schema(
          rawSchema: inputSchema, context: .init(dialect: .draft2020_12)
        )
        #expect(try requestSchema.validate(JSONValue.parse(input)).isValid)
        expectNoDifference(
          postOperation["requestBody"]?["content"]?["application/json"]?["schema"]?["$ref"],
          .string("#/components/schemas/CreateUser")
        )
        let post = try await client.post("/api/v1/users") { request in
          request.headers[.contentType] = "application/json"
          request.body = .init(data: input)
        }
        try await assertSuccess(
          post, status: 201, expected: User(id: 42, name: "Created"), operation: postOperation, spec: spec
        )
        expectNoDifference(postOperation["requestBody"]?["required"], .boolean(true))
        expectNoDifference(postOperation["responses"]?["201"]?["content"]?["application/json"]?["schema"]?["$ref"], .string("#/components/schemas/User"))
        let invalidBody = try await client.post("/api/v1/users") { request in
          request.headers[.contentType] = "application/json"
          request.body = .init(string: "{\"name\":42}")
        }
        #expect(try !requestSchema.validate(JSONValue.parse("{\"name\":42}")).isValid)
        try await assertError(invalidBody, status: 400, operation: postOperation, spec: spec)
        let unauthorized = try await client.get("/api/v1/me")
        try await assertError(unauthorized, status: 401, operation: try #require(spec["paths"]?["/api/v1/me"]?["get"]), spec: spec)
        let authorized = try await client.get("/api/v1/me", headers: [.authorization: "Bearer fixture-token"])
        expectNoDifference(authorized.status.code, 200)
        let currentUser = try await authorized.content.decode(User.self)
        expectNoDifference(currentUser, User(id: 1, name: "Authenticated"))
        let anonymous = try await client.get("/api/v1/feed")
        expectNoDifference(anonymous.status.code, 200)
        let anonymousUser = try await anonymous.content.decode(User.self)
        expectNoDifference(anonymousUser, User(id: 1, name: "Anonymous"))
        let feed = try await client.get("/api/v1/feed", headers: [.authorization: "Bearer fixture-token"])
        expectNoDifference(feed.status.code, 200)
        let feedUser = try await feed.content.decode(User.self)
        expectNoDifference(feedUser, User(id: 1, name: "Authenticated"))
        let opaque = try await client.get("/api/v1/opaque")
        expectNoDifference(opaque.status.code, 200)
        let opaqueText = try await opaque.body.requireString()
        expectNoDifference(opaqueText, "Still native")
      }
    }
  }

  private func assertSuccess(
    _ response: ClientResponse, status: Int, expected: User, operation: JSONValue, spec: JSONValue
  ) async throws {
    expectNoDifference(response.status.code, status)
    expectNoDifference(response.headers[.contentType], "application/json")
    var responseBody = response.body
    let data = try #require(await responseBody.collect())
    expectNoDifference(try JSONDecoder().decode(User.self, from: data), expected)
    try validateBody(JSONValue.parse(data), status: status, operation: operation, spec: spec)
  }

  private func assertError(
    _ response: ClientResponse, status: Int, operation: JSONValue, spec: JSONValue
  ) async throws {
    expectNoDifference(response.status.code, status)
    #expect(response.headers[.contentType]?.hasPrefix("application/json") == true)
    var responseBody = response.body
    let body = try await responseBody.collect()
    let json = try JSONValue.parse(try #require(body))
    expectNoDifference(json["error"], .boolean(true))
    try validateBody(json, status: status, operation: operation, spec: spec)
  }

  private func validateBody(
    _ json: JSONValue, status: Int, operation: JSONValue, spec: JSONValue
  ) throws {
    let reference = try #require(
      operation["responses"]?[String(status)]?["content"]?["application/json"]?["schema"]?["$ref"]?.string
    )
    let name = String(try #require(reference.split(separator: "/").last))
    let definition = try #require(spec["components"]?["schemas"]?[name])
    let schema = try Schema(rawSchema: definition, context: .init(dialect: .draft2020_12))
    #expect(schema.validate(json).isValid)
  }
}
