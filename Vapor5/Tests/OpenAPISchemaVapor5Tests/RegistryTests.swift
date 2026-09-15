import CustomDump
import Foundation
import JSONSchema
import JSONSchemaBuilder
import struct OpenAPISchema.Info
import OpenAPISchemaVapor5
import Testing
import Vapor
import VaporTesting

@Suite struct RegistryTests {
  private func descriptor(
    _ id: String = "get", method: String = "GET", path: [String] = ["users"],
    parameters: [OpenAPIParameter] = [],
    responses: [OpenAPIResponse] = [.json(200, User.self)],
    security: OpenAPISecurity = .publicAccess
  ) -> OpenAPIRouteDescriptor {
    .init(
      method: method, path: path, operationID: id, parameters: parameters,
      responses: responses, security: security
    )
  }

  @Test func collisionsAndFailuresAreAtomic() async throws {
    try await withApp { app in
      let registry = OpenAPIRegistry(application: app, info: Info(title: "Atomic", version: "1"))
      try await registry.register(descriptors: [descriptor()]) { routes in
        routes.get("users") { _ in JSONResponse(User(id: 1, name: "A")) }
      }
      let original = try registry.encodeCanonicalJSON()
      let routeCount = app.routes.all.count
      let failures: [OpenAPIRouteDescriptor] = [
        descriptor("get", path: ["duplicate-id"]),
        descriptor("collision", path: ["collision"], responses: [.json(200, CreateUser.self, name: "User")]),
        descriptor("method", method: "BREW", path: ["method"]),
        descriptor("auth", path: ["auth"], security: .required("missing")),
        descriptor("responses", path: ["responses"], responses: [.empty(200), .empty(200)]),
        descriptor("bodyless", path: ["bodyless"], responses: [.json(204, User.self)]),
        descriptor("parameter", path: ["parameter"], parameters: [.path("absent", Int.self)]),
        descriptor("duplicate", path: ["duplicate"], parameters: [.query("q", String.self), .query("q", Int.self)]),
        descriptor("header", path: ["header"], parameters: [.header("X-Test", String.self), .header("x-test", String.self)]),
        descriptor("reserved", path: ["reserved"], parameters: [.header("Authorization", String.self)]),
      ]
      for failure in failures {
        await #expect(throws: (any Error).self) {
          try await registry.register(descriptors: [failure]) { routes in
            routes.on(.init(rawValue: failure.method)!, failure.path.map { .constant($0) }) { _ in "OK" }
          }
        }
        expectNoDifference(app.routes.all.count, routeCount)
        expectNoDifference(try registry.encodeCanonicalJSON(), original)
      }
      await #expect(throws: (any Error).self) {
        try await registry.register(descriptors: [descriptor("missing", path: ["missing"])]) { routes in
          routes.get("other") { _ in "Not a matching route" }
        }
      }
      await #expect(throws: (any Error).self) {
        try await registry.register(descriptors: []) { routes in
          routes.get("partial") { _ in "Should never register" }
          throw OpenAPIContractError("boot failed")
        }
      }
      expectNoDifference(app.routes.all.count, routeCount)
      expectNoDifference(try registry.encodeCanonicalJSON(), original)
    }
  }

  @Test func sameNameDifferentLocationsAndRequiredPaths() async throws {
    try await withApp { app in
      let registry = OpenAPIRegistry(application: app, info: Info(title: "Parameters", version: "1"))
      try await registry.register(descriptors: [
        descriptor(path: ["things", ":id"], parameters: [
          .query("id", String.self), .header("id", String.self),
        ])
      ]) { routes in
        routes.get("things", ":id") { _ in "OK" }
      }
      let parameters = try #require(
        registry.document().rawValue["paths"]?["/things/{id}"]?["get"]?["parameters"]?.array
      )
      expectNoDifference(parameters.count, 3)
      expectNoDifference(parameters.map { $0["in"] }, [.string("header"), .string("path"), .string("query")])
      expectNoDifference(parameters[1]["required"], .boolean(true))
      await #expect(throws: (any Error).self) {
        try await registry.register(descriptors: [
          descriptor("optionalPath", path: ["bad", ":id"], parameters: [
            OpenAPIParameter("id", in: .path, required: false, schema: .integer())
          ])
        ]) { routes in
          routes.get("bad", ":id") { _ in "OK" }
        }
      }
    }
  }

  @Test func finalRouteDuplicatesAndEquivalentCaptureShapesFail() async throws {
    try await withApp { app in
      let registry = OpenAPIRegistry(application: app, info: Info(title: "Duplicate", version: "1"))
      await #expect(throws: (any Error).self) {
        try await registry.register(descriptors: [descriptor(path: ["users", ":id"])]) { routes in
          routes.get("users", ":id") { _ in "first" }
          routes.get("users", ":other") { _ in "second" }
        }
      }
      expectNoDifference(app.routes.all.count, 0)
      try await registry.register(descriptors: [descriptor()]) { routes in
        routes.get("users") { _ in "first" }
      }
      app.get("users") { _ in "second" }
      #expect(throws: OpenAPIContractError.self) { try registry.document() }
    }
  }

  @Test func sharedComponentsAndOrderAreDeterministic() async throws {
    try await withApp { first in
      try await withApp { second in
        let a = OpenAPIRegistry(application: first, info: Info(title: "Order", version: "1"))
        let b = OpenAPIRegistry(application: second, info: Info(title: "Order", version: "1"))
        let descriptors = [
          descriptor("z", path: ["z"], responses: [.json(200, User.self)]),
          descriptor("a", path: ["a"], responses: [.json(200, User.self)]),
        ]
        for registry in [a, b] {
          try await registry.register(descriptors: registry === a ? descriptors : descriptors.reversed()) { routes in
            routes.get("z") { _ in "z" }
            routes.get("a") { _ in "a" }
          }
        }
        expectNoDifference(try a.encodeCanonicalJSON(), try b.encodeCanonicalJSON())
        expectNoDifference(try a.document().rawValue["components"]?["schemas"]?.object?.count, 1)
      }
    }
  }

  @Test func malformedPathsFailWithoutRoutingParserTrap() async throws {
    try await withApp { app in
      let registry = OpenAPIRegistry(application: app, info: Info(title: "Paths", version: "1"))
      for path in [[":bad{"], ["a/b"], ["*"], ["**"], [":"], [""]] {
        await #expect(throws: OpenAPIContractError.self) {
          try await registry.register(descriptors: [descriptor(path: path)]) { _ in }
        }
      }
      expectNoDifference(app.routes.all.count, 0)
    }
  }

  @Test func registryRejectsReentrantRegistration() async throws {
    try await withApp { app in
      let registry = OpenAPIRegistry(application: app, info: Info(title: "Reentrant", version: "1"))
      await #expect(throws: OpenAPIContractError.self) {
        try await registry.register(descriptors: []) { _ in
          try await registry.register(descriptors: []) { _ in }
        }
      }
      expectNoDifference(app.routes.all.count, 0)
    }
  }

  @Test func sharedCapturePrefixesWithDifferentTailsAreRejectedAtomically() async throws {
    try await withApp { app in
      let registry = OpenAPIRegistry(application: app, info: Info(title: "Captures", version: "1"))
      app.get("users", ":id", "posts") { _ in "posts" }
      let original = try registry.encodeCanonicalJSON()
      await #expect(throws: OpenAPIContractError.self) {
        try await registry.register(descriptors: [
          descriptor("settings", path: ["users", ":name", "settings"])
        ]) { routes in
          routes.get("users", ":name", "settings") { _ in "settings" }
        }
      }
      expectNoDifference(app.routes.all.count, 1)
      expectNoDifference(try registry.encodeCanonicalJSON(), original)
      try await registry.register(descriptors: [
        descriptor("settings", path: ["users", ":id", "settings"])
      ]) { routes in
        routes.get("users", ":id", "settings") { _ in "settings" }
      }
      expectNoDifference(app.routes.all.count, 2)
      // The same structural prefix under a different method is a separate native trie branch.
      try await registry.register(descriptors: [
        descriptor("update", method: "POST", path: ["users", ":name", "settings"])
      ]) { routes in
        routes.post("users", ":name", "settings") { _ in "updated" }
      }
      expectNoDifference(app.routes.all.count, 3)
    }
  }

  @Test func caseInsensitiveRoutingIsRejectedAtRegistrationAndExport() async throws {
    try await withApp { app in
      let registry = OpenAPIRegistry(application: app, info: Info(title: "Case", version: "1"))
      app.routes.caseInsensitive = true
      await #expect(throws: OpenAPIContractError.self) {
        try await registry.register(descriptors: [descriptor()]) { routes in
          routes.get("users") { _ in "documented" }
        }
      }
      expectNoDifference(app.routes.all.count, 0)
      app.routes.caseInsensitive = false
      try await registry.register(descriptors: [descriptor()]) { routes in
        routes.get("users") { _ in "documented" }
      }
      app.get("Users") { _ in "undocumented override" }
      app.routes.caseInsensitive = true
      #expect(throws: OpenAPIContractError.self) { try registry.document() }
      #expect(throws: OpenAPIContractError.self) { try registry.encodeCanonicalJSON() }
    }
  }

  @Test func resetContentAllowsEmptyButNotJSON() async throws {
    try await withApp { app in
      let registry = OpenAPIRegistry(application: app, info: Info(title: "No body", version: "1"))
      await #expect(throws: OpenAPIContractError.self) {
        try await registry.register(descriptors: [
          descriptor("invalid", responses: [.json(205, User.self)])
        ]) { routes in
          routes.get("users") { _ in "invalid" }
        }
      }
      expectNoDifference(app.routes.all.count, 0)
      try await registry.register(descriptors: [
        descriptor("reset", responses: [.empty(205)])
      ]) { routes in
        routes.get("users") { _ in Vapor.Response(status: .resetContent) }
      }
      expectNoDifference(
        try registry.document().rawValue["paths"]?["/users"]?["get"]?["responses"]?["205"]?["content"],
        nil
      )
      app.get("invalid-json") { request in
        await #expect(throws: OpenAPIContractError.self) {
          try await JSONResponse(User(id: 1, name: "No body"), status: 205).encodeResponse(for: request)
        }
        return Vapor.Response(status: .resetContent)
      }
      try await app.testing { client in
        let response = try await client.get("/users")
        expectNoDifference(response.status.code, 205)
        let empty = try await response.body.string()
        #expect(empty == nil || empty == "")
        let rejected = try await client.get("/invalid-json")
        expectNoDifference(rejected.status.code, 205)
      }
    }
  }
}
