// swift-tools-version: 6.4
import Foundation
import PackageDescription

let selected = ProcessInfo.processInfo.environment["OPENAPI_FAILURE"] ?? "MissingRequestSchema"
let fixtures = ["MissingRequestSchema", "MissingResponseSchema", "OpaqueResponse", "RawResponse", "MalformedAnnotation"]
precondition(fixtures.contains(selected), "Unknown OPENAPI_FAILURE fixture")

let package = Package(
  name: "CompileFailures",
  platforms: [.macOS("26.2")],
  dependencies: [
    .package(name: "swift-openapi-schema-vapor5", path: "../.."),
    .package(
      url: "https://github.com/vapor/vapor.git",
      revision: "bce76e99119568a3c782b76bcf4c9891f757fdbe"
    ),
    .package(url: "https://github.com/ajevans99/swift-json-schema.git", from: "0.14.0"),
  ],
  targets: [
    .executableTarget(
      name: "CompileFailure",
      dependencies: [
        .product(name: "OpenAPIVaporMacros", package: "swift-openapi-schema-vapor5"),
        .product(name: "VaporMacros", package: "vapor"),
        .product(name: "JSONSchemaBuilder", package: "swift-json-schema"),
      ],
      path: "Sources",
      exclude: fixtures.filter { $0 != selected }.map { "\($0).swift" },
      sources: ["\(selected).swift"]
    )
  ]
)
