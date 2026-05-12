# Swift OpenAPI Schema Vapor

`swift-openapi-schema-vapor` is a Vapor 4 companion package for
[`swift-openapi-schema`](https://github.com/ajevans99/swift-openapi-schema).
It lets an existing Vapor app attach OpenAPI metadata directly to routes and
then generate an `OpenAPIDocument` from the registered route collection.

The package is intentionally small and manual today, so a future Vapor 5 macro
package can build on the same typed helpers.

## Installation

Add the package to your `Package.swift` dependencies:

```swift
.package(url: "https://github.com/ajevans99/swift-openapi-schema-vapor.git", branch: "main")
```

Then add the product to your Vapor target:

```swift
.product(name: "OpenAPISchemaVapor", package: "swift-openapi-schema-vapor")
```

Import it alongside Vapor:

```swift
import OpenAPISchemaVapor
import Vapor
```

## Documenting routes

Call `route.documented(...)` on the `Route` returned from a Vapor route
registration. The metadata is stored on the route and read later when the app
builds an OpenAPI document.

```swift
import JSONSchemaBuilder
import OpenAPISchema
import OpenAPISchemaVapor
import Vapor

@Schemable
struct CreatePet: Content {
  let name: String
  let tag: String?
}

@Schemable
struct Pet: Content {
  let id: String
  let name: String
  let tag: String?
}

app.openAPI.info = Info(title: "Pets API", version: "1.0.0")
app.openAPI.servers = [
  Server("https://api.example.com", description: "Production")
]

app.post("pets") { req async throws -> Pet in
  let body = try req.content.decode(CreatePet.self)
  return try await createPet(body)
}
.documented(
  operationID: "createPet",
  tags: ["Pets"],
  summary: "Create a pet",
  requestBody: .json(CreatePet.self),
  responses: [
    .json(.created, Pet.self)
  ]
)
```

### Typed request and response bodies

Use `.json(CreatePet.self)` for JSON request bodies and
`.json(.created, Pet.self)` for JSON responses. These helpers require the Vapor
types to conform to both the Vapor protocol (`Content` or `ResponseEncodable`)
and `Schemable`, so missing schema support fails at compile time.

Any `Schemable` types referenced by typed request or response helpers are
automatically registered under `components.schemas` in generated documents.
Repeated references are de-duplicated by component name.

### Path and query parameters

Vapor `:parameter` path components are converted to OpenAPI `{parameter}`
segments. If you do not provide explicit metadata for a path parameter, the
generator adds a required string path parameter automatically.

Use `PathParameter` and `QueryParameter` to control schema, requiredness, and
descriptions:

```swift
app.get("pets", ":petID") { req async throws -> Pet in
  let id = req.parameters.get("petID")!
  return try await findPet(id)
}
.documented(
  operationID: "getPet",
  tags: ["Pets"],
  parameters: [
    PathParameter("petID", schema: .string(format: "uuid")),
    QueryParameter("includeToys", schema: .boolean, description: "Include toy data")
  ],
  responses: [
    .json(.ok, Pet.self)
  ]
)
```

## Generating a document

After routes are registered, call `app.openAPI.document()` to build and validate
an `OpenAPIDocument`:

```swift
let document = try app.openAPI.document()
let jsonData = try document.encodeCanonicalJSON()
```

The document uses `app.openAPI.info` and `app.openAPI.servers`. Only routes with
`route.documented(...)` metadata are included.

## Known limitations

- Only routes explicitly marked with `documented(...)` are emitted.
- The current API is manual; the Vapor 5 macro direction is planned but not part
  of this package yet.
- Untyped request/response bodies require lower-level `OpenAPISchema` builders.
- Non-standard Vapor HTTP methods currently fall back to `GET`.
- Runtime route handler behavior is not introspected; keep the documentation
  metadata in sync with your handlers.

## Vapor 5 macro direction

The planned Vapor 5 proof of concept should live in separate macro targets and
use an aggregate macro such as `@OpenAPIController` to read marker annotations
like `@RequestBody`, `@Response`, `@Path`, and `@Query`. The macro-generated
code should call the same generic helpers used by this manual API.
