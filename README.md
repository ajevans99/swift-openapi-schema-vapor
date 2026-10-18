# Swift OpenAPI Schema Vapor

`swift-openapi-schema-vapor` is a Vapor 4 companion package for
[`swift-openapi-schema`](https://github.com/ajevans99/swift-openapi-schema).
It lets an existing Vapor app attach OpenAPI metadata directly to routes and
then generate an `OpenAPIDocument` from the registered route collection.

The root package remains a small, manual Vapor 4 integration. An isolated
[Vapor 5 native-macro prototype](Vapor5/README.md) lives in `Vapor5/`, with its
own Swift 6.4 dependency graph, runtime registry, companion metadata macros,
and runnable external-consumer fixture.

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
    .json(.ok, Pet.self)
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
Repeated references to the same schema are de-duplicated by component name.
Registering two different schemas under one name throws
`OpenAPISchemaVaporError.conflictingComponentSchema`.

### Raw schemas and other media types

Types that are not `Schemable` can still be documented. Reference a named
component and register its raw JSON Schema alongside the body:

```swift
.documented(
  operationID: "listStores",
  responses: [
    .json(.ok, schema: .array(.component("Store")), schemas: [
      .component("Store", raw: ["type": "object", "required": ["id"]])
    ])
  ]
)
```

Use `init(mediaType:schema:)` for request bodies and
`init(_:mediaType:schema:)` for responses with any media type, such as
`application/octet-stream` uploads or `text/event-stream` streams. Request
bodies are required by default; pass `required: false` for optional bodies.
Responses may declare headers:

```swift
.documented(
  operationID: "uploadPetPhoto",
  requestBody: .init(mediaType: .octetStream, schema: .binaryString, required: false),
  responses: [
    .empty(.created, headers: ["Location": .init(schema: .string(format: "uri"), required: true)])
  ]
)
```

### Path, query, and header parameters

Vapor `:parameter` path components are converted to OpenAPI `{parameter}`
segments. If you do not provide `.path` metadata for a path parameter, the
generator adds a required string path parameter automatically. A parameter is
identified by its name and location, so a query parameter never stands in for a
path parameter with the same name. Documenting a path parameter the route does
not have, or repeating a name and location, throws.

Use `PathParameter`, `QueryParameter`, and `HeaderParameter` to control schema,
requiredness, and descriptions:

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

### Security and extensions

Register security schemes once, then declare each operation's requirement.
`security: nil` (the default) omits the operation's `security` field; this
package does not set document-level security, so such an operation declares no
requirement. `.anonymous` emits `security: []` to state that explicitly, and
`.required` lists alternatives that each map scheme names to scopes.
Requirements may only reference registered schemes.

```swift
app.openAPI.securitySchemes = [
  BearerAuth("petToken"),
  APIKeyAuth("storeSession", in: .cookie, keyName: "store_session"),
  APIKeyAuth("storeCSRF", in: .header, keyName: "X-Store-CSRF"),
]

app.get("pets", ":petID") { req async throws -> Pet in try await findPet(req) }
  .documented(
    operationID: "getPet",
    responses: [.json(.ok, Pet.self)],
    security: .scheme("petToken", scopes: ["pets:read"]),
    extensions: ["x-rate-limit": 100]
  )

app.post("stores") { req async throws -> Store in try await createStore(req) }
  .documented(
    operationID: "createStore",
    responses: [.json(.created, Store.self)],
    security: .required([["storeSession": [], "storeCSRF": []]])
  )
```

`extensions` adds specification extensions to the operation. Keys must start
with `x-`.

## Generating a document

After routes are registered, call `app.openAPI.documentJSON()` to build the
complete document, validated against the OpenAPI 3.1 meta-schema, and encode it
with `OpenAPICanonicalJSON.encode(_:)`:

```swift
let json = try app.openAPI.documentJSON()
let jsonData = try OpenAPICanonicalJSON.encode(json)
```

The document uses `app.openAPI.info` and `app.openAPI.servers`. Only routes with
`route.documented(...)` metadata are included; `app.openAPI.undocumentedRoutes()`
lists the rest, so a test can require complete coverage. Documented routes with
`*` or `**` path components throw, because OpenAPI path templates cannot express
them. `serveJSON(at:)` serves the same bytes.

`app.openAPI.document()` returns the core `OpenAPIDocument`. The core cannot yet
express operation extensions, explicit security, response headers, or optional
request bodies, so that value omits them and marks every request body required.
`documentJSON()` applies them to the JSON representation before validation.

### One document per path prefix

An API with several route families can build one document per prefix. Matching
routes are included, the prefix is removed from their paths, and `servers`
defaults to the prefix (`/api/v1` here). Pass `servers` to use absolute URLs
instead. The prefix must contain only constant components:

```swift
let json = try app.openAPI.documentJSON(
  info: Info(title: "Pets API", version: "1.0.0"),
  including: ["api", "v1"],
  securitySchemes: [BearerAuth("petToken")]
)
```

`document(info:servers:including:stripping:securitySchemes:)` takes a route
predicate instead, and throws if a selected route lacks the prefix.

## Checking responses against the document

`OpenAPIResponseValidator` keeps handlers and the document in parity. Given an
operation and an actual response, it checks that the status is documented,
required headers are present, the media type is declared, and a JSON body
validates against the documented schema:

```swift
let validator = OpenAPIResponseValidator(document: try app.openAPI.documentJSON())
try await app.testing().test(.POST, "pets", beforeRequest: { req in
  try req.content.encode(CreatePet(name: "Bird", tag: nil))
}) { response in
  #expect(validator.validate(
    operationID: "createPet",
    status: response.status,
    headers: response.headers,
    body: response.body
  ).isEmpty)
}
```

A handler that returns Vapor's default `200` while the document promises `201`
is reported as `createPet returned status 200, but documents only [201].`

## Known limitations

- Only routes explicitly marked with `documented(...)` are emitted; use
  `undocumentedRoutes()` to enforce coverage.
- The root product is manual; the Vapor 5 prototype is a separate local package,
  not a root product or remotely selectable SwiftPM subdirectory product.
- HTTP methods without an OpenAPI counterpart (for example `CONNECT` or custom
  methods) throw `OpenAPISchemaVaporError.unsupportedHTTPMethod`.
- Runtime route handler behavior is not introspected; use
  `OpenAPIResponseValidator` in tests to keep handlers and metadata in sync.
- `OpenAPISchemaValue.object(properties:)` emits properties in dictionary order;
  prefer `Schemable` types or raw schemas when byte-stable output matters.

## Vapor 5 prototype

See [Vapor5/README.md](Vapor5/README.md) for native `@Controller` routing plus
metadata-only `@OpenAPIController`, explicit JSON/body/security contracts,
group-aware staged registration, and HTTP/spec parity tests. The root Vapor 4
dependency and runtime behavior are unchanged; the two Vapor major versions
must not be resolved in one package graph.
