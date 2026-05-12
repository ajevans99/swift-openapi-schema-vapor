# Swift OpenAPI Schema Vapor

`swift-openapi-schema-vapor` is a companion package for
[`swift-openapi-schema`](https://github.com/ajevans99/swift-openapi-schema).
It starts with a Vapor 4 manual API and is structured so a Vapor 5 macro package
can be added later.

```swift
import OpenAPISchemaVapor

app.openAPI.info = Info(title: "Pets API", version: "1.0.0")

app.post("pets") { req async throws -> Pet in
  let body = try req.content.decode(CreatePet.self)
  return try await createPet(body)
}
.documented(
  operationID: "createPet",
  requestBody: .json(CreatePet.self),
  responses: [
    .json(.created, Pet.self)
  ]
)

let document = try app.openAPI.document()
```

The typed request and response helpers require Vapor content/response types to
also conform to `Schemable`, so missing schema support fails at compile time.

## Vapor 5 macro direction

The planned Vapor 5 proof of concept should live in separate macro targets and
use an aggregate macro such as `@OpenAPIController` to read marker annotations
like `@RequestBody`, `@Response`, `@Path`, and `@Query`. The macro-generated
code should call the same generic helpers used by this manual API.
