// swift-tools-version: 6.4
import CompilerPluginSupport
import PackageDescription

let package = Package(
  name: "swift-openapi-schema-vapor5",
  platforms: [.macOS("26.2")],
  products: [
    .library(name: "OpenAPISchemaVapor5", targets: ["OpenAPISchemaVapor5"]),
    .library(name: "OpenAPIVaporMacros", targets: ["OpenAPIVaporMacros"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/vapor/vapor.git",
      revision: "bce76e99119568a3c782b76bcf4c9891f757fdbe"
    ),
    .package(url: "https://github.com/ajevans99/swift-openapi-schema.git", exact: "0.2.0"),
    .package(url: "https://github.com/ajevans99/swift-json-schema.git", from: "0.14.0"),
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-macro-testing.git", from: "0.6.0"),
    .package(url: "https://github.com/pointfreeco/swift-custom-dump.git", from: "1.0.0"),
  ],
  targets: [
    .target(
      name: "OpenAPISchemaVapor5",
      dependencies: [
        .product(name: "Vapor", package: "vapor"),
        .product(name: "OpenAPISchema", package: "swift-openapi-schema"),
        .product(name: "JSONSchemaBuilder", package: "swift-json-schema"),
      ]
    ),
    .macro(
      name: "OpenAPIVaporMacrosPlugin",
      dependencies: [
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
        .product(name: "SwiftDiagnostics", package: "swift-syntax"),
      ]
    ),
    .target(
      name: "OpenAPIVaporMacros",
      dependencies: ["OpenAPIVaporMacrosPlugin", "OpenAPISchemaVapor5"]
    ),
    .testTarget(
      name: "OpenAPISchemaVapor5Tests",
      dependencies: [
        "OpenAPISchemaVapor5",
        "OpenAPIVaporMacros",
        .product(name: "VaporMacros", package: "vapor"),
        .product(name: "VaporTesting", package: "vapor"),
        .product(name: "CustomDump", package: "swift-custom-dump"),
      ]
    ),
    .testTarget(
      name: "OpenAPIVaporMacrosTests",
      dependencies: [
        "OpenAPIVaporMacrosPlugin",
        .product(name: "MacroTesting", package: "swift-macro-testing"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
