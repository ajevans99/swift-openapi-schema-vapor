// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "swift-openapi-schema-vapor",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(
      name: "OpenAPISchemaVapor",
      targets: ["OpenAPISchemaVapor"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/ajevans99/swift-openapi-schema.git", .upToNextMinor(from: "0.2.0")),
    .package(url: "https://github.com/vapor/vapor.git", from: "4.115.0"),
    .package(url: "https://github.com/ajevans99/swift-json-schema.git", .upToNextMinor(from: "0.14.0")),
    .package(url: "https://github.com/apple/swift-collections.git", from: "1.5.0"),
  ],
  targets: [
    .target(
      name: "OpenAPISchemaVapor",
      dependencies: [
        .product(name: "OpenAPISchema", package: "swift-openapi-schema"),
        .product(name: "Vapor", package: "vapor"),
        .product(name: "JSONSchema", package: "swift-json-schema"),
        .product(name: "JSONSchemaBuilder", package: "swift-json-schema"),
        .product(name: "OrderedJSON", package: "swift-json-schema"),
        .product(name: "OrderedCollections", package: "swift-collections"),
      ]
    ),
    .testTarget(
      name: "OpenAPISchemaVaporTests",
      dependencies: [
        "OpenAPISchemaVapor",
        .product(name: "OpenAPISchema", package: "swift-openapi-schema"),
        .product(name: "Vapor", package: "vapor"),
        .product(name: "VaporTesting", package: "vapor"),
        .product(name: "JSONSchemaBuilder", package: "swift-json-schema"),
        .product(name: "OrderedJSON", package: "swift-json-schema"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
