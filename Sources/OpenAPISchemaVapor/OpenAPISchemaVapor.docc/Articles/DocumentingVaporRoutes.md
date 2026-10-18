# Documenting Vapor Routes

Attach OpenAPI metadata to Vapor routes and generate a document from the app.

## Define schema-backed content

Typed JSON helpers require Vapor content types that also conform to `Schemable`.

```swift
import JSONSchemaBuilder
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
```

## Add route documentation

Use `route.documented(...)` after registering the Vapor route. The typed
`.json(CreatePet.self)` request body and `.json(.created, Pet.self)` response
both reference Swift types and register their schemas automatically.

```swift
import OpenAPISchema
import OpenAPISchemaVapor

app.openAPI.info = Info(title: "Pets API", version: "1.0.0")

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

## Describe parameters

Path parameters are inferred from Vapor `:parameter` route components when no
explicit metadata is provided. Add `PathParameter` or `QueryParameter` entries
when you need descriptions, formats, or non-string schemas.

```swift
app.get("pets", ":petID") { req async throws -> Pet in
  let id = req.parameters.get("petID")!
  return try await findPet(id)
}
.documented(
  operationID: "getPet",
  parameters: [
    PathParameter("petID", schema: .string(format: "uuid")),
    QueryParameter("includeToys", schema: .boolean)
  ],
  responses: [
    .json(.ok, Pet.self)
  ]
)
```

## Generate JSON

Build the OpenAPI document after registering routes.

```swift
let json = try app.openAPI.documentJSON()
let data = try OpenAPICanonicalJSON.encode(json)
```

`documentJSON()` is the complete document, validated against the OpenAPI 3.1
meta-schema. `document()` returns the core `OpenAPIDocument`, which cannot yet
express operation security, extensions, response headers, or optional request
bodies; it omits them and marks every request body required.

Only documented routes are included. Keep route documentation synchronized with
handler behavior because this package does not introspect handler bodies.
