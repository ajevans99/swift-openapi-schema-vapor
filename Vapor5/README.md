# Vapor 5 native routing prototype

This **isolated Swift 6.4 package** preserves the repository root's Vapor 4
product. It pins Vapor to revision `bce76e99119568a3c782b76bcf4c9891f757fdbe`
and OpenAPISchema to 0.2.0, with resolved dependency lockfiles. macOS 26.2 or
later is required. No global Xcode/toolchain configuration change is needed.

This is a local prototype layout, **not a remotely selectable SwiftPM
subdirectory product**. Clone the repository and depend on its `Vapor5`
directory with `.package(path: ".../swift-openapi-schema-vapor/Vapor5")`.
Do not put both Vapor 4 and Vapor 5 in a single package graph.

## Run

From the repository root:

```sh
swift test                            # unchanged Vapor 4 package
swift test --package-path Vapor5      # runtime, native HTTP, and macro tests
bash Vapor5/verify-consumers.sh       # separate consuming package + expected compiler failures
swift run --package-path Vapor5/Examples/NativeApp NativeApp
```

The example runs a native Vapor server. In another terminal:

```sh
curl -i http://localhost:8080/api/v1/pets/7
curl -i http://localhost:8080/api/v1/pets \
  -H 'Content-Type: application/json' -d '{"name":"Mochi"}'
```

The POST returns **201**, `application/json`, and `{"id":42,"name":"Mochi"}`.
`NativeApp --print-spec` prints the fixture's generated OpenAPI without starting
a server. It is not a general-purpose export command or Swagger UI.

## Native routes, companion metadata

```swift
import JSONSchemaBuilder
import struct OpenAPISchema.Info
import OpenAPISchemaVapor5
import OpenAPIVaporMacros
import Vapor
import VaporMacros

@Schemable
struct CreatePet: Content { let name: String }

@Schemable
struct Pet: Content { let id: Int; let name: String }

@OpenAPIController
@Controller
struct Pets {
  @GET("pets", Int.self)
  @OpenAPIOperation("getPet")
  func get(req: Request, id: Int) async throws -> JSONResponse<Pet> {
    JSONResponse(Pet(id: id, name: "Mochi"))
  }

  @POST("pets")
  @OpenAPIOperation("createPet", status: 201)
  @OpenAPIRequestBody(CreatePet.self)
  func create(req: Request) async throws -> JSONResponse<Pet> {
    let input = try await req.content.decode(CreatePet.self)
    return JSONResponse(Pet(id: 42, name: input.name), status: 201)
  }
}

let registry = OpenAPIRegistry(
  application: app, info: Info(title: "Pets", version: "1.0.0")
)
try await registry.register(Pets(), at: ["api", "v1"])
let document = try registry.document() // OpenAPIJSONDocument, final structural validation
let bytes = try registry.encodeCanonicalJSON()
```

Native `@Controller` still emits the only `boot(routes:)`, and native HTTP
macros still extract path captures and authentication, call handlers, and
encode responses. `@OpenAPIController` reads original annotated method syntax,
emits only `openAPIRoutes` and an `OpenAPIControllerMetadata` conformance, and
does not depend on the expansion order of other macros. Both controller
attribute orders are exercised by compiled consumers.

Import individual OpenAPISchema builders (as above), rather than the entire
module in controller files: both Vapor and OpenAPISchema define `Request` and
`Response`, and the native Vapor macros currently emit those names unqualified.

`Int.self` means the **native stored capture `int0`**, not the handler label
`id`. The spec therefore contains `/api/v1/pets/{int0}` and a required integer
parameter. This prototype deliberately offers **no capture alias rewriting**.
There is no body, query, or header argument binding: decoding stays explicit
in the handler.

## Explicit contracts

Only methods marked `@OpenAPIOperation` are documented. Unmarked native routes,
including opaque responses, keep working and are absent from the spec.

| Annotation | Meaning |
| --- | --- |
| `@OpenAPIOperation("uniqueID", status: 201)` | Explicit success status (default 200); infers only the model inside `JSONResponse<Model>` |
| `@OpenAPIRequestBody(Input.self)` | Required JSON request body; `Input` must be `Codable & Schemable` |
| `@OpenAPIQuery("name", String.self, required: false)` | Scalar query contract, manually decoded |
| `@OpenAPIHeader("X-Trace", String.self, required: true)` | Scalar header contract, manually read/enforced |
| `@OpenAPIError(404, FailureBody.self)` | Additional explicit JSON error response |
| `@OpenAPISecurity("bearer")` | Explicit required scheme, not inferred from an auth user type |
| `@OpenAPISecurity("bearer", optional: true)` | Anonymous OR authenticated security alternatives |

Declare schemes in the registry, e.g. `securitySchemes: [BearerAuth("bearer")]`.
Required security is `[{"bearer":[]}]`; optional security is `[{},{"bearer":[]}]`.
The native `@AuthMiddleware(User.self, middleware)` remains authoritative at
runtime. A documented native auth route must explicitly name its scheme;
optional/required metadata must match its auth parameter. Merely declaring a
security scheme does not install authentication.

The bounded attached-native support is `@GET`, `@POST`, `@PUT`, `@PATCH`, and
`@DELETE`. Documented `@HTTP`, freestanding/`on:` routing, opaque, raw
`Response`, streaming, and arbitrary `ResponseEncodable` return types are
diagnosed, rather than incorrectly described as JSON. Unmarked routes using
those native capabilities remain native. Malformed markers and unsupported
syntax also produce diagnostics. Supported scalar parameter types are
`String`, `Int`, `Double`, `Bool`, and `UUID`; runtime manual helpers can use
explicit `OpenAPIParameterValue` conformances.

## Manual pipeline and registration boundary

For routes without companion macros, create `OpenAPIRouteDescriptor` values
and stage registrations using:

```swift
try await registry.register(descriptors: [
  .init(
    method: "GET", path: ["api", "pets", ":id"], operationID: "getPet",
    parameters: [.path("id", Int.self)],
    responses: [.json(200, Pet.self)]
  )
]) { root in
  root.grouped("api").get("pets", ":id") { request in
    let id = try request.parameters.require("id", as: Int.self)
    return JSONResponse(Pet(id: id, name: "Mochi"))
  }
}
```

The recording builder must be the **root**; put all groups **inside** this
closure. Descriptors name the final registered method/path, including those
groups. The convenience controller API uses only literal `at:` prefixes and
applies them consistently to routing and metadata. It intentionally does not
accept an arbitrary outer `RoutesBuilder`, whose transformations cannot be
observed reliably. Manual descriptors can also describe captured group
parameters. No returned `Route` copy is annotated or mutated.

Registration is sequential configuration-time work, before application
startup/freeze. The registry stages routes, checks descriptor matches against
the current transaction, validates the complete candidate document, then
commits routes and metadata. A throwing boot or failed contract validation
does not partially register routes. Configure only through the supplied
recording builder inside the closure; side effects on a separately captured
application cannot be rolled back.

The registry rejects duplicate operation IDs, method/path pairs, ambiguous
native capture shapes and incompatible capture names at shared trie prefixes
(even when trailing paths differ), conflicting component definitions, duplicate parameter
identities `(name, location)`, optional path parameters, invalid bodyless
statuses, unsupported methods, and undeclared security schemes. Header names
are case-insensitive. A query/header sharing a path parameter's name does not
suppress the required path parameter. Wildcards and partial captures are
unsupported documentation paths. Matching component names with equal schemas
are reused; explicit `name:` arguments on manual body/response helpers can
disambiguate differing models.

Case-insensitive native routing is not supported: registration and export both
reject `app.routes.caseInsensitive == true`, including a configuration change
after earlier registrations. JSON bodies are rejected for HTTP 204, 205, and
304; manual `.empty(205)` remains supported.

Generation uses OpenAPISchema's builders and JSONSchemaBuilder's
`Schemable.schema.definition()`. Only `requestBody.required` and security
alternatives are added through `OpenAPIJSONDocument` because the current
builder DSL cannot express them. The **final augmented document** is validated.
Operations, parameters, statuses, schemas, and schemes have deterministic
ordering.

## Wire contract limits

`JSONResponse<Model>` uses a dedicated Foundation JSON encoder with ISO8601
dates, default coding keys, and sorted keys, and emits `application/json`.
It deliberately does not call a model's custom `ResponseEncodable` or
`Content.beforeEncode`. The handler's actual status must match its annotation:
`status: 201` in metadata does not change a response created with default 200.
The integration fixture verifies both statuses, media types, bodies, query
and header behavior, and default Vapor JSON errors against generated schemas,
in memory and through a real HTTP server.

`Codable & Schemable` is a compile-time capability check, **not proof that an
arbitrary custom encoder matches a schema**. Custom `CodingKeys`,
`encode(to:)`/`init(from:)`, date properties, key strategies, or Content
decoding hooks require an explicitly matching schema and wire tests. Do not
assume synthesized `@Schemable` describes those customizations. Request
decoding uses the app's native content configuration and must likewise agree.
No automatic runtime validation middleware, response rewriting, error
inference, OAuth scope inference, auth installation, or streaming schemas are
provided.
