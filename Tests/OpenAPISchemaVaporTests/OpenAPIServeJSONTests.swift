import Foundation
import OpenAPISchema
import OpenAPISchemaVapor
import Testing
import Vapor
import VaporTesting

@Suite("OpenAPI JSON serving")
struct OpenAPIServeJSONTests {
  @Test
  func serveJSONRegistersGETRouteServingCanonicalDocument() async throws {
    try await withApp { app in
      app.openAPI.info = Info(title: "Pets API", version: "1.0.0")
      app.openAPI.serveJSON(at: "openapi.json")
      app.get("pets") { _ async throws -> String in
        "ok"
      }
      .documented(
        operationID: "listPets",
        tags: ["Pets"],
        summary: "List pets",
        responses: [.empty(.ok)]
      )

      let expectedBody = String(decoding: try app.openAPI.document().encodeCanonicalJSON(), as: UTF8.self)

      try await app.testing().test(.GET, "/openapi.json") { response in
        #expect(response.status == .ok)
        #expect(response.headers.contentType == .json)

        var body = response.body
        let bodyString = body.readString(length: body.readableBytes)
        let responseBody = try #require(bodyString)
        #expect(responseBody == expectedBody)

        let data = Data(responseBody.utf8)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["openapi"] as? String == "3.1.0")

        let info = try #require(json["info"] as? [String: Any])
        #expect(info["title"] as? String == "Pets API")
        #expect(info["version"] as? String == "1.0.0")

        let paths = try #require(json["paths"] as? [String: Any])
        let petsPath = try #require(paths["/pets"] as? [String: Any])
        let getOperation = try #require(petsPath["get"] as? [String: Any])
        #expect(getOperation["operationId"] as? String == "listPets")
        #expect(paths["/openapi.json"] == nil)
      }
    }
  }
}
