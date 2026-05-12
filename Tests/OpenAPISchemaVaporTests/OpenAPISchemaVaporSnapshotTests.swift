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
        "components" : {
          "schemas" : {
            "SnapshotCreatePet" : {
              "properties" : {
                "name" : {
                  "type" : "string"
                }
              },
              "required" : [
                "name"
              ],
              "type" : "object"
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
              "required" : [
                "id",
                "name"
              ],
              "type" : "object"
            }
          }
        },
        "info" : {
          "description" : "Snapshot coverage for Vapor-generated OpenAPI JSON.",
          "title" : "Pets API",
          "version" : "1.0.0"
        },
        "openapi" : "3.1.0",
        "paths" : {
          "\\/pets" : {
            "post" : {
              "operationId" : "createPet",
              "requestBody" : {
                "content" : {
                  "application\\/json" : {
                    "schema" : {
                      "$ref" : "#\\/components\\/schemas\\/SnapshotCreatePet"
                    }
                  }
                },
                "required" : true
              },
              "responses" : {
                "201" : {
                  "content" : {
                    "application\\/json" : {
                      "schema" : {
                        "$ref" : "#\\/components\\/schemas\\/SnapshotPet"
                      }
                    }
                  },
                  "description" : "Created pet"
                }
              },
              "summary" : "Create a pet",
              "tags" : [
                "Pets"
              ]
            }
          },
          "\\/pets\\/{petID}" : {
            "get" : {
              "operationId" : "getPet",
              "parameters" : [
                {
                  "description" : "Pet identifier",
                  "in" : "path",
                  "name" : "petID",
                  "required" : true,
                  "schema" : {
                    "format" : "uuid",
                    "type" : "string"
                  }
                },
                {
                  "description" : "Include toy data",
                  "in" : "query",
                  "name" : "includeToys",
                  "required" : false,
                  "schema" : {
                    "type" : "boolean"
                  }
                }
              ],
              "responses" : {
                "200" : {
                  "content" : {
                    "application\\/json" : {
                      "schema" : {
                        "$ref" : "#\\/components\\/schemas\\/SnapshotPet"
                      }
                    }
                  },
                  "description" : "OK"
                }
              },
              "summary" : "Get a pet",
              "tags" : [
                "Pets"
              ]
            }
          }
        },
        "servers" : [
          {
            "description" : "Production",
            "url" : "https:\\/\\/api.example.com"
          }
        ]
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
