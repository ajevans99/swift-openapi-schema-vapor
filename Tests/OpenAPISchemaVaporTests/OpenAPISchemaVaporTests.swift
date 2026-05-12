import JSONSchemaBuilder
import OpenAPISchema
import OpenAPISchemaVapor
import Testing
import Vapor

@Schemable
struct CreatePet: Content {
  let name: String
  let tag: String?
}

@Schemable
struct Pet: Content {
  let id: String
  let name: String
  let tag: String?
}

@Suite("OpenAPI Schema Vapor")
struct OpenAPISchemaVaporTests {
  @Test
  func documentedRouteBuildsOpenAPIDocument() async throws {
    try await withApp { app in
      app.openAPI.info = Info(title: "Pets API", version: "1.0.0")
      app.post("pets") { request async throws -> Pet in
        let input = try request.content.decode(CreatePet.self)
        return Pet(id: UUID().uuidString, name: input.name, tag: input.tag)
      }
      .documented(
        operationID: "createPet",
        tags: ["Pets"],
        summary: "Create a pet",
        requestBody: .json(CreatePet.self),
        responses: [
          .json(.created, Pet.self)
        ]
      )

      let document = try app.openAPI.document()
      let json = try document.jsonValue()

      #expect(json.object?["paths"]?.object?["/pets"] != nil)
      #expect(json.object?["components"]?.object?["schemas"]?.object?["CreatePet"] != nil)
      #expect(json.object?["components"]?.object?["schemas"]?.object?["Pet"] != nil)
    }
  }

  @Test
  func documentedRouteAddsImplicitPathParameter() async throws {
    try await withApp { app in
      app.get("pets", ":petID") { _ async throws -> String in
        "ok"
      }
      .documented(
        operationID: "getPet",
        responses: [
          .empty(.ok)
        ]
      )

      let json = try app.openAPI.document().jsonValue()
      let parameters = json.object?["paths"]?.object?["/pets/{petID}"]?
        .object?["get"]?.object?["parameters"]?.array

      #expect(parameters?.first?.object?["name"] == "petID")
      #expect(parameters?.first?.object?["in"] == "path")
    }
  }
}

private func withApp(_ body: (Application) async throws -> Void) async throws {
  let app = try await Application.make(.testing)
  do {
    try await body(app)
    try await app.asyncShutdown()
  } catch {
    try? await app.asyncShutdown()
    throw error
  }
}
