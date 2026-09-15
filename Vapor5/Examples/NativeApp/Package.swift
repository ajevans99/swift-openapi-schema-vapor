// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "NativeApp",
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
      name: "NativeApp",
      dependencies: [
        .product(name: "OpenAPIVaporMacros", package: "swift-openapi-schema-vapor5"),
        .product(name: "VaporMacros", package: "vapor"),
        .product(name: "JSONSchemaBuilder", package: "swift-json-schema"),
      ]
    )
  ]
)
