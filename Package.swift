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
    .package(url: "https://github.com/ajevans99/swift-openapi-schema.git", branch: "main"),
    .package(url: "https://github.com/vapor/vapor.git", from: "4.115.0"),
    .package(url: "https://github.com/ajevans99/swift-json-schema.git", branch: "main"),
  ],
  targets: [
    .target(
      name: "OpenAPISchemaVapor",
      dependencies: [
        .product(name: "OpenAPISchema", package: "swift-openapi-schema"),
        .product(name: "Vapor", package: "vapor"),
        .product(name: "JSONSchemaBuilder", package: "swift-json-schema"),
      ]
    ),
    .testTarget(
      name: "OpenAPISchemaVaporTests",
      dependencies: [
        "OpenAPISchemaVapor",
        .product(name: "OpenAPISchema", package: "swift-openapi-schema"),
        .product(name: "Vapor", package: "vapor"),
        .product(name: "JSONSchemaBuilder", package: "swift-json-schema"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
