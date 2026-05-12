import Foundation
import JSONSchemaBuilder
import OpenAPISchema
import OpenAPISchemaVapor
import Testing
import Vapor

@Schemable
struct SnapshotCreatePet: Content {
  let name: String
}

@Schemable
struct SnapshotPet: Content {
  let id: String
  let name: String
}

@Suite("OpenAPI Schema Vapor snapshots")
struct OpenAPISchemaVaporSnapshotTests {
  @Test
  func generatedDocumentCanonicalJSONMatchesSnapshot() async throws {
    try await withSnapshotApp { app in
      app.openAPI.info = Info(
        title: "Pets API",
        version: "1.0.0",
        description: "Snapshot coverage for Vapor-generated OpenAPI JSON."
      )
      app.openAPI.servers = [
        Server("https://api.example.com", description: "Production")
      ]

      app.post("pets") { request async throws -> SnapshotPet in
        let input = try request.content.decode(SnapshotCreatePet.self)
        return SnapshotPet(id: "pet-1", name: input.name)
      }
      .documented(
        operationID: "createPet",
        tags: ["Pets"],
        summary: "Create a pet",
        requestBody: .json(SnapshotCreatePet.self),
        responses: [
          .json(.created, SnapshotPet.self, description: "Created pet")
        ]
      )

      app.get("pets", ":petID") { _ async throws -> SnapshotPet in
        SnapshotPet(id: "pet-1", name: "Bird")
      }
      .documented(
        operationID: "getPet",
        tags: ["Pets"],
        summary: "Get a pet",
        parameters: [
          PathParameter("petID", schema: .string(format: "uuid"), description: "Pet identifier"),
          QueryParameter("includeToys", schema: .boolean, description: "Include toy data"),
        ],
        responses: [
          .json(.ok, SnapshotPet.self)
        ]
      )

      let actualJSON = String(decoding: try app.openAPI.document().encodeCanonicalJSON(), as: UTF8.self)
      let expectedJSON = """
      {
        "openapi" : "3.1.0",
        "info" : {
          "title" : "Pets API",
          "version" : "1.0.0",
          "description" : "Snapshot coverage for Vapor-generated OpenAPI JSON."
        },
        "paths" : {
          "/pets" : {
            "post" : {
              "operationId" : "createPet",
              "tags" : [
                "Pets"
              ],
              "summary" : "Create a pet",
              "requestBody" : {
                "required" : true,
                "content" : {
                  "application/json" : {
                    "schema" : {
                      "$ref" : "#/components/schemas/SnapshotCreatePet"
                    }
                  }
                }
              },
              "responses" : {
                "201" : {
                  "description" : "Created pet",
                  "content" : {
                    "application/json" : {
                      "schema" : {
                        "$ref" : "#/components/schemas/SnapshotPet"
                      }
                    }
                  }
                }
              }
            }
          },
          "/pets/{petID}" : {
            "get" : {
              "operationId" : "getPet",
              "tags" : [
                "Pets"
              ],
              "summary" : "Get a pet",
              "parameters" : [
                {
                  "name" : "petID",
                  "in" : "path",
                  "required" : true,
                  "schema" : {
                    "type" : "string",
                    "format" : "uuid"
                  },
                  "description" : "Pet identifier"
                },
                {
                  "name" : "includeToys",
                  "in" : "query",
                  "required" : false,
                  "schema" : {
                    "type" : "boolean"
                  },
                  "description" : "Include toy data"
                }
              ],
              "responses" : {
                "200" : {
                  "description" : "OK",
                  "content" : {
                    "application/json" : {
                      "schema" : {
                        "$ref" : "#/components/schemas/SnapshotPet"
                      }
                    }
                  }
                }
              }
            }
          }
        },
        "servers" : [
          {
            "url" : "https://api.example.com",
            "description" : "Production"
          }
        ],
        "components" : {
          "schemas" : {
            "SnapshotCreatePet" : {
              "properties" : {
                "name" : {
                  "type" : "string"
                }
              },
              "type" : "object",
              "required" : [
                "name"
              ]
            },
            "SnapshotPet" : {
              "properties" : {
                "id" : {
                  "type" : "string"
                },
                "name" : {
                  "type" : "string"
                }
              },
              "type" : "object",
              "required" : [
                "id",
                "name"
              ]
            }
          }
        }
      }
      """ + "\n"

      if actualJSON != expectedJSON {
        Issue.record("Actual JSON:\n\(actualJSON)")
      }
      #expect(actualJSON == expectedJSON)
    }
  }
}

private func withSnapshotApp(_ body: (Application) async throws -> Void) async throws {
  let app = try await Application.make(.testing)
  do {
    try await body(app)
    try await app.asyncShutdown()
  } catch {
    try? await app.asyncShutdown()
    throw error
  }
}
