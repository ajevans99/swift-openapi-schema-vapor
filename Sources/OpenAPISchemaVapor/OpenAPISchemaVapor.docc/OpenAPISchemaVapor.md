# ``OpenAPISchemaVapor``

Generate OpenAPI documents from documented Vapor routes.

## Overview

OpenAPISchemaVapor connects Vapor route registration with
`swift-openapi-schema`. Mark routes with `documented(...)`, describe typed JSON
request and response bodies, and generate a validated `OpenAPIDocument` from the
application.

```swift
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

Types used with the typed JSON helpers must conform to `Schemable`. Their
schemas are registered automatically in `components.schemas`.

## Topics

### Essentials

- <doc:DocumentingVaporRoutes>
