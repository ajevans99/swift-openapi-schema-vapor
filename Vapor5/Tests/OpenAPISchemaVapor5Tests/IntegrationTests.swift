import CustomDump
import Foundation
import JSONSchema
import JSONSchemaBuilder
import struct OpenAPISchema.Info
import OpenAPISchemaVapor5
import Testing
import Vapor
import VaporMacros
import VaporTesting

extension JSONValue {
  subscript(_ key: String) -> JSONValue? { object?[key] }
  subscript(_ index: Int) -> JSONValue? {
    guard let array, array.indices.contains(index) else { return nil }
    return array[index]
  }
}

@Schemable
struct CreateUser: Content, Equatable {
  let name: String
}

@Schemable
struct User: Content, Equatable {
  let id: Int
  let name: String
}

@Controller
struct ManualUsers {
  @GET("users", Int.self)
  func get(req: Request, id: Int) async throws -> JSONResponse<User> {
    JSONResponse(User(id: id, name: "Blob"))
  }

  @POST("users")
  func create(req: Request) async throws -> JSONResponse<User> {
    let input = try await req.content.decode(CreateUser.self)
    return JSONResponse(User(id: 42, name: input.name), status: 201)
  }
}

@Suite struct IntegrationTests {
  @Test func manualNativeRoutesAndSchema() async throws {
    try await withApp { app in
      let registry = OpenAPIRegistry(application: app, info: Info(title: "Users", version: "1"))
      try await registry.register(descriptors: [
        .init(
          method: "GET", path: ["api", "v1", "users", ":int0"], operationID: "getUser",
          parameters: [.path("int0", Int.self)], responses: [.json(200, User.self)]
        ),
        .init(
          method: "POST", path: ["api", "v1", "users"], operationID: "createUser",
          requestBody: .json(CreateUser.self), responses: [.json(201, User.self)]
        ),
      ]) { routes in
        try await routes.grouped("api").grouped("v1").register(collection: ManualUsers())
      }
      let json = try registry.document().rawValue
      expectNoDifference(json["openapi"], .string("3.1.0"))
      expectNoDifference(
        json["paths"]?["/api/v1/users/{int0}"]?["get"]?["parameters"]?[0]?["schema"]?["type"],
        .string("integer")
      )
      expectNoDifference(
        json["paths"]?["/api/v1/users"]?["post"]?["requestBody"]?["required"], .boolean(true)
      )
      expectNoDifference(
        json["paths"]?["/api/v1/users"]?["post"]?["responses"]?["201"]?["content"]?["application/json"]?["schema"]?["$ref"],
        .string("#/components/schemas/User")
      )
      expectNoDifference(try registry.encodeCanonicalJSON(), try registry.encodeCanonicalJSON())
      try await app.testing { client in
        let get = try await client.get("/api/v1/users/7")
        expectNoDifference(get.status.code, 200)
        expectNoDifference(get.headers[.contentType], "application/json")
        let fetched = try await get.content.decode(User.self)
        expectNoDifference(fetched, User(id: 7, name: "Blob"))
        let post = try await client.post("/api/v1/users", content: CreateUser(name: "Alice"))
        expectNoDifference(post.status.code, 201)
        expectNoDifference(post.headers[.contentType], "application/json")
        let created = try await post.content.decode(User.self)
        expectNoDifference(created, User(id: 42, name: "Alice"))
      }
    }
  }
}