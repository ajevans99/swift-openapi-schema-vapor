import Foundation
import JSONSchemaBuilder
import OpenAPISchema
import OpenAPISchemaVapor
import OrderedJSON
import Testing
import Vapor
import VaporTesting

@Schemable
struct Store: Content {
  let id: String
  let name: String
}

@Suite("OpenAPI Schema Vapor operations")
struct OpenAPIOperationTests {
  @Test
  func everyStandardMethodMapsToItsOperation() async throws {
    try await withGenericApp { app in
      let methods: [Vapor.HTTPMethod] = [.GET, .PUT, .POST, .DELETE, .PATCH, .HEAD, .OPTIONS, .TRACE]
      for method in methods {
        app.on(method, "pets") { _ in Vapor.HTTPStatus.noContent }
          .documented(operationID: "pets\(method.rawValue)", responses: [.empty(.noContent)])
      }

      let item = try #require(try app.openAPI.documentJSON().object?["paths"]?.object?["/pets"]?.object)
      #expect(Set(item.keys) == ["get", "put", "post", "delete", "patch", "head", "options", "trace"])
      for method in methods {
        #expect(item[method.rawValue.lowercased()]?.object?["operationId"]?.string == "pets\(method.rawValue)")
      }
    }
  }

  @Test
  func nonstandardMethodThrowsInsteadOfFallingBackToGET() async throws {
    try await withGenericApp { app in
      app.on(.RAW(value: "PURGE"), "pets") { _ in Vapor.HTTPStatus.noContent }
        .documented(operationID: "purgePets", responses: [.empty(.noContent)])

      #expect(throws: OpenAPISchemaVaporError.unsupportedHTTPMethod(method: "PURGE", path: "/pets")) {
        try app.openAPI.document()
      }
    }
  }

  @Test
  func sameNamedQueryParameterDoesNotSuppressPathParameter() async throws {
    try await withGenericApp { app in
      app.get("pets", ":petID") { _ in Vapor.HTTPStatus.noContent }
        .documented(
          operationID: "getPet",
          parameters: [QueryParameter("petID", description: "Alternate lookup")],
          responses: [.empty(.noContent)]
        )

      let parameters = try #require(
        try app.openAPI.documentJSON().object?["paths"]?.object?["/pets/{petID}"]?.object?["get"]?
          .object?["parameters"]?.array)
      let identities = parameters.compactMap { parameter -> String? in
        guard let name = parameter.object?["name"]?.string, let location = parameter.object?["in"]?.string
        else { return nil }
        return "\(location):\(name)"
      }
      #expect(identities == ["path:petID", "query:petID"])
    }
  }

  @Test
  func documentedPathParameterMustExistOnTheRoute() async throws {
    try await withGenericApp { app in
      app.get("pets", ":petID") { _ in Vapor.HTTPStatus.noContent }
        .documented(
          operationID: "getPet",
          parameters: [PathParameter("storeID")],
          responses: [.empty(.noContent)]
        )

      #expect(
        throws: OpenAPISchemaVaporError.unknownPathParameter(
          operationID: "getPet", path: "/pets/{petID}", name: "storeID")
      ) {
        try app.openAPI.document()
      }
    }
  }

  @Test
  func repeatedParameterIdentityThrows() async throws {
    try await withGenericApp { app in
      app.get("pets") { _ in Vapor.HTTPStatus.noContent }
        .documented(
          operationID: "listPets",
          parameters: [QueryParameter("limit"), HeaderParameter("limit"), QueryParameter("limit")],
          responses: [.empty(.noContent)]
        )

      #expect(
        throws: OpenAPISchemaVaporError.duplicateParameter(
          operationID: "listPets", name: "limit", location: "query")
      ) {
        try app.openAPI.document()
      }
    }
  }

  @Test
  func differentSchemasUnderOneComponentNameThrow() async throws {
    try await withGenericApp { app in
      let storeA: JSONValue = ["type": "object", "properties": ["id": ["type": "string"]]]
      let storeB: JSONValue = ["type": "object", "properties": ["id": ["type": "integer"]]]
      app.get("stores") { _ in Vapor.HTTPStatus.noContent }
        .documented(
          operationID: "listStores",
          responses: [.json(.ok, schema: .array(.component("Store")), schemas: [.component("Store", raw: storeA)])]
        )
      app.get("stores", "featured") { _ in Vapor.HTTPStatus.noContent }
        .documented(
          operationID: "featuredStore",
          responses: [.json(.ok, schema: .component("Store"), schemas: [.component("Store", raw: storeA)])]
        )

      // Identical duplicates are merged.
      let schemas = try #require(
        try app.openAPI.documentJSON().object?["components"]?.object?["schemas"]?.object)
      #expect(schemas["Store"] == storeA)

      app.get("stores", "closed") { _ in Vapor.HTTPStatus.noContent }
        .documented(
          operationID: "closedStore",
          responses: [.json(.ok, schema: .component("Store"), schemas: [.component("Store", raw: storeB)])]
        )
      #expect(throws: OpenAPISchemaVaporError.conflictingComponentSchema(name: "Store")) {
        try app.openAPI.document()
      }
    }
  }

  @Test
  func securityIsExplicitAndReferencesRegisteredSchemes() async throws {
    try await withGenericApp { app in
      app.openAPI.securitySchemes = [
        BearerAuth("petToken"),
        APIKeyAuth("storeSession", in: .cookie, keyName: "store_session"),
        APIKeyAuth("storeCSRF", in: .header, keyName: "X-Store-CSRF"),
      ]
      app.get("pets") { _ in Vapor.HTTPStatus.noContent }
        .documented(
          operationID: "listPets",
          responses: [.empty(.noContent)],
          security: .scheme("petToken", scopes: ["pets:read"])
        )
      app.get("pets", "count") { _ in Vapor.HTTPStatus.noContent }
        .documented(operationID: "countPets", responses: [.empty(.noContent)], security: .anonymous)
      app.post("stores") { _ in Vapor.HTTPStatus.noContent }
        .documented(
          operationID: "createStore",
          responses: [.empty(.noContent)],
          security: .required([["storeSession": [], "storeCSRF": []], ["petToken": []]])
        )
      app.get("stores") { _ in Vapor.HTTPStatus.noContent }
        .documented(operationID: "listStores", responses: [.empty(.noContent)])

      let json = try app.openAPI.documentJSON()
      let paths = try #require(json.object?["paths"]?.object)
      #expect(paths["/pets"]?.object?["get"]?.object?["security"] == [["petToken": ["pets:read"]]])
      #expect(paths["/pets/count"]?.object?["get"]?.object?["security"] == .array([]))
      #expect(
        paths["/stores"]?.object?["post"]?.object?["security"]
          == [["storeCSRF": [], "storeSession": []], ["petToken": []]])
      #expect(paths["/stores"]?.object?["get"]?.object?["security"] == nil)
      let schemes = try #require(json.object?["components"]?.object?["securitySchemes"]?.object)
      #expect(schemes["storeSession"] == ["type": "apiKey", "in": "cookie", "name": "store_session"])

      app.delete("stores") { _ in Vapor.HTTPStatus.noContent }
        .documented(operationID: "deleteStores", responses: [.empty(.noContent)], security: .scheme("adminToken"))
      #expect(
        throws: OpenAPISchemaVaporError.unknownSecurityScheme(operationID: "deleteStores", scheme: "adminToken")
      ) {
        try app.openAPI.document()
      }
    }
  }

  @Test
  func extensionsRequireTheVendorPrefix() async throws {
    try await withGenericApp { app in
      app.get("pets") { _ in Vapor.HTTPStatus.noContent }
        .documented(
          operationID: "listPets",
          responses: [.empty(.noContent)],
          extensions: ["x-rate-limit": 10, "x-audience": "public"]
        )

      let operation = try #require(
        try app.openAPI.documentJSON().object?["paths"]?.object?["/pets"]?.object?["get"]?.object)
      #expect(operation["x-rate-limit"] == 10)
      #expect(Array(operation.keys.suffix(2)) == ["x-audience", "x-rate-limit"])

      app.get("stores") { _ in Vapor.HTTPStatus.noContent }
        .documented(operationID: "listStores", responses: [.empty(.noContent)], extensions: ["rate-limit": 10])
      #expect(throws: OpenAPISchemaVaporError.invalidExtensionKey(operationID: "listStores", key: "rate-limit")) {
        try app.openAPI.document()
      }
    }
  }

  @Test
  func headersOptionalBodiesAndNonJSONMediaTypes() async throws {
    try await withGenericApp { app in
      app.post("pets", ":petID", "photo") { _ in Vapor.HTTPStatus.created }
        .documented(
          operationID: "uploadPetPhoto",
          requestBody: .init(
            mediaType: .octetStream,
            schema: .binaryString,
            required: false,
            description: "Photo bytes"
          ),
          responses: [
            .empty(
              .created,
              headers: ["Location": .init(schema: .string(format: "uri"), description: "Photo URL", required: true)]
            )
          ]
        )
      app.get("pets", "events") { _ in Vapor.HTTPStatus.ok }
        .documented(
          operationID: "streamPetEvents",
          responses: [.init(.ok, mediaType: "text/event-stream", schema: .string(), description: "Pet events")]
        )

      let paths = try #require(try app.openAPI.documentJSON().object?["paths"]?.object)
      let upload = try #require(paths["/pets/{petID}/photo"]?.object?["post"]?.object)
      #expect(
        upload["requestBody"]
          == [
            "description": "Photo bytes",
            "required": false,
            "content": ["application/octet-stream": ["schema": ["type": "string", "format": "binary"]]],
          ])
      #expect(
        upload["responses"]?.object?["201"]
          == [
            "description": "Created",
            "headers": [
              "Location": [
                "description": "Photo URL", "required": true, "schema": ["type": "string", "format": "uri"],
              ]
            ],
          ])
      #expect(
        Array(upload["responses"]?.object?["201"]?.object?.keys ?? []) == ["description", "headers"])
      let stream = try #require(paths["/pets/events"]?.object?["get"]?.object)
      #expect(
        stream["responses"]?.object?["200"]?.object?["content"] == ["text/event-stream": ["schema": ["type": "string"]]]
      )
    }
  }

  @Test
  func undocumentedRoutesAreReported() async throws {
    try await withGenericApp { app in
      app.get("pets") { _ in Vapor.HTTPStatus.noContent }
        .documented(operationID: "listPets", responses: [.empty(.noContent)])
      app.get("stores") { _ in Vapor.HTTPStatus.noContent }
      app.get("health") { _ in Vapor.HTTPStatus.noContent }

      #expect(
        app.openAPI.undocumentedRoutes().map { "\($0.method.rawValue) /\($0.path.string)" }
          == ["GET /stores", "GET /health"])
    }
  }

  @Test
  func prefixedDocumentsIncludeAndStripTheirPrefix() async throws {
    try await withGenericApp { app in
      let v1 = app.grouped("api", "v1")
      v1.get("pets", ":petID") { _ in Vapor.HTTPStatus.noContent }
        .documented(operationID: "getPet", responses: [.empty(.noContent)])
      app.grouped("api", "v2").get("stores") { _ in Vapor.HTTPStatus.noContent }
        .documented(operationID: "listStores", responses: [.empty(.noContent)])

      let json = try app.openAPI.documentJSON(
        info: Info(title: "Pets v1", version: "1.0.0"),
        servers: [OpenAPISchema.Server("/api/v1")],
        including: ["api", "v1"]
      )
      #expect(json.object?["paths"]?.object.map { Array($0.keys) } == ["/pets/{petID}"])
      #expect(json.object?["servers"] == [["url": "/api/v1"]])

      #expect(
        throws: OpenAPISchemaVaporError.routeOutsidePrefix(
          operationID: "listStores", path: "/api/v2/stores", prefix: "/api/v1")
      ) {
        try app.openAPI.document(
          info: Info(title: "All", version: "1.0.0"),
          including: { $0.openAPIDocumentation != nil },
          stripping: ["api", "v1"]
        )
      }
    }
  }

  @Test
  func prefixedDocumentsDefaultTheirServerToThePrefix() async throws {
    try await withGenericApp { app in
      app.grouped("api", "v1").get("pets") { _ in Vapor.HTTPStatus.noContent }
        .documented(operationID: "listPets", responses: [.empty(.noContent)])

      let json = try app.openAPI.documentJSON(
        info: Info(title: "Pets v1", version: "1.0.0"),
        including: ["api", "v1"]
      )
      #expect(json.object?["paths"]?.object.map { Array($0.keys) } == ["/pets"])
      #expect(json.object?["servers"] == [["url": "/api/v1"]])
    }
  }

  @Test
  func parameterizedPrefixThrows() async throws {
    try await withGenericApp { app in
      // A server URL cannot carry the path parameter, so the stripped path would have no
      // `{ownerID}` template for the parameter Vapor still requires.
      app.grouped("owners", ":ownerID").get("pets") { _ in Vapor.HTTPStatus.noContent }
        .documented(operationID: "listOwnerPets", responses: [.empty(.noContent)])

      #expect(throws: OpenAPISchemaVaporError.nonConstantPrefix(prefix: "/owners/{ownerID}")) {
        try app.openAPI.documentJSON(
          info: Info(title: "Owners", version: "1.0.0"),
          including: ["owners", ":ownerID"]
        )
      }
    }
  }

  @Test
  func wildcardRoutesThrowInsteadOfBecomingLiteralPaths() async throws {
    try await withGenericApp { app in
      app.get("files", "**") { _ in Vapor.HTTPStatus.noContent }
        .documented(operationID: "getFile", responses: [.empty(.noContent)])

      #expect(
        throws: OpenAPISchemaVaporError.unsupportedPathComponent(
          operationID: "getFile", path: "/files/**", component: "**")
      ) {
        try app.openAPI.documentJSON()
      }
    }
  }

  @Test
  func completeDocumentValidatesAgainstTheMetaSchema() async throws {
    try await withGenericApp { app in
      app.openAPI.securitySchemes = [BearerAuth("petToken")]
      app.post("pets") { _ in Vapor.HTTPStatus.created }
        .documented(
          operationID: "createPet",
          requestBody: .json(schema: .component("NewPet"), schemas: [.component("NewPet", raw: ["type": "object"])]),
          responses: [.empty(.created, headers: ["Location": .init(required: true)])],
          security: .anonymous,
          extensions: ["x-idempotent": false]
        )

      let json = try app.openAPI.documentJSON()
      let result = try OpenAPIValidator.validate(OpenAPIJSONDocument(rawValue: json))
      #expect(result.isValid)
      let data = try OpenAPICanonicalJSON.encode(json)
      #expect(data.last == UInt8(ascii: "\n"))
      #expect(try JSONValue.parse(data) == json)
    }
  }
}

@Suite("OpenAPI response parity")
struct OpenAPIResponseParityTests {
  @Test
  func handlerStatusThatDisagreesWithTheDocumentIsCaught() async throws {
    try await withGenericApp { app in
      // The handler returns Vapor's default 200, but the document promises 201.
      app.post("stores") { request async throws -> Store in
        Store(id: "store-1", name: try request.content.get(String.self, at: "name"))
      }
      .documented(operationID: "createStore", responses: [.json(.created, Store.self)])

      let validator = OpenAPIResponseValidator(document: try app.openAPI.documentJSON())
      try await app.testing().test(
        .POST, "stores",
        beforeRequest: { request in try request.content.encode(["name": "Corner"]) }
      ) { response in
        #expect(response.status == .ok)
        let problems = validator.validate(
          operationID: "createStore", status: response.status, headers: response.headers, body: response.body)
        #expect(problems == ["createStore returned status 200, but documents only [201]."])
      }
    }
  }

  @Test
  func matchingResponseIsAcceptedAndSchemaViolationsAreReported() async throws {
    try await withGenericApp { app in
      app.get("stores", ":storeID") { request async throws -> Vapor.Response in
        let id = try request.parameters.require("storeID")
        if id == "broken" {
          return try await ["id": id].encodeResponse(for: request)
        }
        return try await Store(id: id, name: "Corner").encodeResponse(for: request)
      }
      .documented(
        operationID: "getStore",
        responses: [.json(.ok, Store.self), .empty(.notFound)]
      )

      let validator = OpenAPIResponseValidator(document: try app.openAPI.documentJSON())
      try await app.testing().test(.GET, "stores/store-1") { response in
        #expect(
          validator.validate(
            operationID: "getStore", status: response.status, headers: response.headers, body: response.body
          ).isEmpty)
      }
      try await app.testing().test(.GET, "stores/broken") { response in
        let problems = validator.validate(
          operationID: "getStore", status: response.status, headers: response.headers, body: response.body)
        #expect(problems.count == 1)
        #expect(problems.first?.hasPrefix("getStore 200 response body: ") == true, "\(problems)")
      }

      let missingHeader = OpenAPIResponseValidator(document: [
        "openapi": "3.1.0",
        "paths": [
          "/stores": [
            "post": [
              "operationId": "createStore",
              "responses": ["201": ["description": "Created", "headers": ["Location": ["required": true]]]],
            ]
          ]
        ],
      ])
      #expect(
        missingHeader.validate(method: .POST, path: "/stores", status: 201)
          == ["POST /stores 201 response is missing required header 'Location'."])
    }
  }

  @Test
  func mediaTypesMatchCaseInsensitivelyWithoutParameters() {
    let validator = OpenAPIResponseValidator(document: [
      "openapi": "3.1.0",
      "paths": [
        "/pets/{petID}/notes": [
          "get": [
            "operationId": "getPetNotes",
            "responses": [
              "200": [
                "description": "OK",
                "content": ["Text/Plain; charset=utf-8": ["schema": ["type": "string"]]],
              ]
            ],
          ]
        ]
      ],
    ])
    var headers = HTTPHeaders()
    headers.replaceOrAdd(name: .contentType, value: "text/plain")
    #expect(
      validator.validate(operationID: "getPetNotes", status: 200, headers: headers, body: Data("Friendly".utf8))
        .isEmpty)

    headers.replaceOrAdd(name: .contentType, value: "application/json")
    #expect(
      validator.validate(operationID: "getPetNotes", status: 200, headers: headers, body: Data("{}".utf8))
        == ["getPetNotes 200 response Content-Type 'application/json' is not one of [Text/Plain; charset=utf-8]."])
  }
}

private func withGenericApp(_ body: (Application) async throws -> Void) async throws {
  let app = try await Application.make(.testing)
  do {
    try await body(app)
    try await app.asyncShutdown()
  } catch {
    try? await app.asyncShutdown()
    throw error
  }
}
