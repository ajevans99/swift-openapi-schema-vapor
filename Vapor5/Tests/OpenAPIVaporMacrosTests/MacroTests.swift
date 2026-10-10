#if os(macOS)
import MacroTesting
import OpenAPIVaporMacrosPlugin
import Testing

@Suite(
  .macros(
    [
      "OpenAPIController": OpenAPIControllerMacro.self,
      "OpenAPIOperation": OpenAPIMarkerMacro.self,
      "OpenAPIRequestBody": OpenAPIMarkerMacro.self,
      "OpenAPIQuery": OpenAPIMarkerMacro.self,
      "OpenAPIHeader": OpenAPIMarkerMacro.self,
      "OpenAPIError": OpenAPIMarkerMacro.self,
      "OpenAPISecurity": OpenAPIMarkerMacro.self,
    ],
    record: .never
  )
)
struct MacroTests {
  @Test func metadataOnlyAndNativeCaptureNames() {
    assertMacro {
      """
      @OpenAPIController
      @Controller
      public struct Users {
        @GET("users", Int.self)
        @OpenAPIOperation("getUser")
        func get(req: Request, id: Int) async throws -> JSONResponse<User> {
          JSONResponse(try await load(id))
        }
      }
      """
    } expansion: {
      """
      @Controller
      public struct Users {
        @GET("users", Int.self)
        func get(req: Request, id: Int) async throws -> JSONResponse<User> {
          JSONResponse(try await load(id))
        }

        public static var openAPIRoutes: [OpenAPISchemaVapor5.OpenAPIRouteDescriptor] {
          [
            OpenAPISchemaVapor5.OpenAPIRouteDescriptor(
              method: "GET",
              path: ["users", ":int0"],
              operationID: "getUser",
              parameters: [.path("int0", Int.self)],
              requestBody: nil,
              responses: [.json(200, User.self)],
              security: .publicAccess
            )
          ]
        }
      }

      extension Users: OpenAPISchemaVapor5.OpenAPIControllerMetadata {
      }
      """
    }
  }

  @Test func reversedAttributeOrderAndAllMethods() {
    assertMacro {
      """
      @Controller
      @OpenAPIController
      struct Routes {
        @OpenAPIOperation("get")
        @GET("items", UUID.self, "parts", String.self)
        func get(req: Request, id: UUID, part: String) -> JSONResponse<Item> {}

        @OpenAPIOperation("post", status: 201)
        @POST("items")
        func post(req: Request) -> JSONResponse<Item> {}

        @PUT("items", Int.self)
        @OpenAPIOperation("put")
        func put(req: Request, id: Int) -> JSONResponse<Item> {}

        @PATCH("items", Double.self)
        @OpenAPIOperation("patch")
        func patch(req: Request, id: Double) -> JSONResponse<Item> {}

        @DELETE("items", Bool.self)
        @OpenAPIOperation("delete", status: 202)
        func delete(req: Request, id: Bool) -> JSONResponse<Item> {}
      }
      """
    } expansion: {
      """
      @Controller
      struct Routes {
        @GET("items", UUID.self, "parts", String.self)
        func get(req: Request, id: UUID, part: String) -> JSONResponse<Item> {}
        @POST("items")
        func post(req: Request) -> JSONResponse<Item> {}

        @PUT("items", Int.self)
        func put(req: Request, id: Int) -> JSONResponse<Item> {}

        @PATCH("items", Double.self)
        func patch(req: Request, id: Double) -> JSONResponse<Item> {}

        @DELETE("items", Bool.self)
        func delete(req: Request, id: Bool) -> JSONResponse<Item> {}

        static var openAPIRoutes: [OpenAPISchemaVapor5.OpenAPIRouteDescriptor] {
          [
            OpenAPISchemaVapor5.OpenAPIRouteDescriptor(
              method: "GET",
              path: ["items", ":uuid0", "parts", ":string1"],
              operationID: "get",
              parameters: [.path("uuid0", UUID.self), .path("string1", String.self)],
              requestBody: nil,
              responses: [.json(200, Item.self)],
              security: .publicAccess
            ),
            OpenAPISchemaVapor5.OpenAPIRouteDescriptor(
              method: "POST",
              path: ["items"],
              operationID: "post",
              parameters: [],
              requestBody: nil,
              responses: [.json(201, Item.self)],
              security: .publicAccess
            ),
            OpenAPISchemaVapor5.OpenAPIRouteDescriptor(
              method: "PUT",
              path: ["items", ":int0"],
              operationID: "put",
              parameters: [.path("int0", Int.self)],
              requestBody: nil,
              responses: [.json(200, Item.self)],
              security: .publicAccess
            ),
            OpenAPISchemaVapor5.OpenAPIRouteDescriptor(
              method: "PATCH",
              path: ["items", ":double0"],
              operationID: "patch",
              parameters: [.path("double0", Double.self)],
              requestBody: nil,
              responses: [.json(200, Item.self)],
              security: .publicAccess
            ),
            OpenAPISchemaVapor5.OpenAPIRouteDescriptor(
              method: "DELETE",
              path: ["items", ":bool0"],
              operationID: "delete",
              parameters: [.path("bool0", Bool.self)],
              requestBody: nil,
              responses: [.json(202, Item.self)],
              security: .publicAccess
            )
          ]
        }
      }

      extension Routes: OpenAPISchemaVapor5.OpenAPIControllerMetadata {
      }
      """
    }
  }

  @Test func bodyParametersErrorsAndRequiredSecurity() {
    assertMacro {
      """
      @OpenAPIController @Controller
      struct Users {
        @POST("users")
        @OpenAPIOperation("create", status: 201)
        @OpenAPIRequestBody(Create.self)
        @OpenAPIQuery("search", String.self, required: false)
        @OpenAPIQuery("page", Int.self, required: true)
        @OpenAPIHeader("X-Trace", String.self, required: true)
        @OpenAPIError(404, NotFound.self)
        @OpenAPIError(422, ValidationError.self)
        @OpenAPISecurity("bearer")
        @AuthMiddleware(User.self, BearerAuthenticator())
        func create(req: Request, user: User) async throws -> JSONResponse<User> {}
      }
      """
    } expansion: {
      """
      @Controller
      struct Users {
        @POST("users")
        @AuthMiddleware(User.self, BearerAuthenticator())
        func create(req: Request, user: User) async throws -> JSONResponse<User> {}

        static var openAPIRoutes: [OpenAPISchemaVapor5.OpenAPIRouteDescriptor] {
          [
            OpenAPISchemaVapor5.OpenAPIRouteDescriptor(
              method: "POST",
              path: ["users"],
              operationID: "create",
              parameters: [.query("search", String.self, required: false), .query("page", Int.self, required: true), .header("X-Trace", String.self, required: true)],
              requestBody: .json(Create.self),
              responses: [.json(201, User.self), .json(404, NotFound.self), .json(422, ValidationError.self)],
              security: .required("bearer")
            )
          ]
        }
      }

      extension Users: OpenAPISchemaVapor5.OpenAPIControllerMetadata {
      }
      """
    }
  }

  @Test func optionalAuthenticationAndParameterDefaults() {
    assertMacro {
      """
      @Controller @OpenAPIController
      struct Users {
        @OpenAPISecurity("bearer", optional: true)
        @OpenAPIQuery("same", String.self)
        @OpenAPIHeader("same", String.self)
        @AuthMiddleware(User.self, BearerAuthenticator())
        @GET("users")
        @OpenAPIOperation("users")
        func users(req: Request, user: User?) -> JSONResponse<[User]> {}

        @GET("optional")
        @OpenAPIOperation("optional")
        @AuthMiddleware(User.self)
        @OpenAPISecurity("bearer", optional: true)
        func optional(req: Request, user: Optional<User>) -> JSONResponse<User> {}
      }
      """
    } expansion: {
      """
      @Controller
      struct Users {
        @AuthMiddleware(User.self, BearerAuthenticator())
        @GET("users")
        func users(req: Request, user: User?) -> JSONResponse<[User]> {}

        @GET("optional")
        @AuthMiddleware(User.self)
        func optional(req: Request, user: Optional<User>) -> JSONResponse<User> {}

        static var openAPIRoutes: [OpenAPISchemaVapor5.OpenAPIRouteDescriptor] {
          [
            OpenAPISchemaVapor5.OpenAPIRouteDescriptor(
              method: "GET",
              path: ["users"],
              operationID: "users",
              parameters: [.query("same", String.self, required: false), .header("same", String.self, required: false)],
              requestBody: nil,
              responses: [.json(200, [User].self)],
              security: .optional("bearer")
            ),
            OpenAPISchemaVapor5.OpenAPIRouteDescriptor(
              method: "GET",
              path: ["optional"],
              operationID: "optional",
              parameters: [],
              requestBody: nil,
              responses: [.json(200, User.self)],
              security: .optional("bearer")
            )
          ]
        }
      }

      extension Users: OpenAPISchemaVapor5.OpenAPIControllerMetadata {
      }
      """
    }
  }

  @Test func qualifiedJSONResponseAndModelReferences() {
    assertMacro {
      """
      @Controller @OpenAPIController
      struct Users {
        @POST
        @OpenAPIOperation("root")
        @OpenAPIRequestBody(API.Create<User>.self)
        @OpenAPIHeader("X-Values", String.self, required: false)
        func root(req: Request) -> OpenAPISchemaVapor5.JSONResponse<API.Page<User>> {}
      }
      """
    } expansion: {
      """
      @Controller
      struct Users {
        @POST
        func root(req: Request) -> OpenAPISchemaVapor5.JSONResponse<API.Page<User>> {}

        static var openAPIRoutes: [OpenAPISchemaVapor5.OpenAPIRouteDescriptor] {
          [
            OpenAPISchemaVapor5.OpenAPIRouteDescriptor(
              method: "POST",
              path: [],
              operationID: "root",
              parameters: [.header("X-Values", String.self, required: false)],
              requestBody: .json(API.Create<User>.self),
              responses: [.json(200, API.Page<User>.self)],
              security: .publicAccess
            )
          ]
        }
      }

      extension Users: OpenAPISchemaVapor5.OpenAPIControllerMetadata {
      }
      """
    }
  }

  @Test func untouchedUndocumentedRoutes() {
    assertMacro {
      """
      @OpenAPIController @Controller
      struct Routes {
        @GET("plain")
        func plain(req: Request) -> String { "hello" }

        @POST("opaque")
        func opaque(req: Request) -> some ResponseEncodable { "hello" }

        @HTTP(.head, "raw")
        @AuthMiddleware(User.self)
        func raw(req: Request, user: User) -> Response {}
      }
      """
    } expansion: {
      """
      @Controller
      struct Routes {
        @GET("plain")
        func plain(req: Request) -> String { "hello" }

        @POST("opaque")
        func opaque(req: Request) -> some ResponseEncodable { "hello" }

        @HTTP(.head, "raw")
        @AuthMiddleware(User.self)
        func raw(req: Request, user: User) -> Response {}

        static var openAPIRoutes: [OpenAPISchemaVapor5.OpenAPIRouteDescriptor] {
          []
        }
      }

      extension Routes: OpenAPISchemaVapor5.OpenAPIControllerMetadata {
      }
      """
    }
  }

  @Test func rejectsNonJSONResponses() {
    assertMacro {
      """
      @OpenAPIController @Controller
      struct Routes {
        @GET("plain") @OpenAPIOperation("plain")
        func plain(req: Request) -> String {}
        @GET("opaque") @OpenAPIOperation("opaque")
        func opaque(req: Request) -> some ResponseEncodable {}
        @GET("raw") @OpenAPIOperation("raw")
        func raw(req: Request) -> Response {}
        @GET("content") @OpenAPIOperation("content")
        func content(req: Request) -> User {}
        @GET("nothing") @OpenAPIOperation("nothing")
        func nothing(req: Request) {}
        @GET("existential") @OpenAPIOperation("existential")
        func existential(req: Request) -> JSONResponse<any Content> {}
        @GET("other") @OpenAPIOperation("other")
        func other(req: Request) -> Other.JSONResponse<User> {}
      }
      """
    } diagnostics: {
      """
      @OpenAPIController @Controller
      struct Routes {
        @GET("plain") @OpenAPIOperation("plain")
        func plain(req: Request) -> String {}
                                 ┬────────
                                 ╰─ 🛑 A documented route must return JSONResponse<ConcreteType>; raw, opaque, streaming, and other response types are not inferred.
        @GET("opaque") @OpenAPIOperation("opaque")
        func opaque(req: Request) -> some ResponseEncodable {}
                                  ┬────────────────────────
                                  ╰─ 🛑 A documented route must return JSONResponse<ConcreteType>; raw, opaque, streaming, and other response types are not inferred.
        @GET("raw") @OpenAPIOperation("raw")
        func raw(req: Request) -> Response {}
                               ┬──────────
                               ╰─ 🛑 A documented route must return JSONResponse<ConcreteType>; raw, opaque, streaming, and other response types are not inferred.
        @GET("content") @OpenAPIOperation("content")
        func content(req: Request) -> User {}
                                   ┬──────
                                   ╰─ 🛑 A documented route must return JSONResponse<ConcreteType>; raw, opaque, streaming, and other response types are not inferred.
        @GET("nothing") @OpenAPIOperation("nothing")
        func nothing(req: Request) {}
             ┬──────
             ╰─ 🛑 A documented route must return JSONResponse<ConcreteType>; raw, opaque, streaming, and other response types are not inferred.
        @GET("existential") @OpenAPIOperation("existential")
        func existential(req: Request) -> JSONResponse<any Content> {}
                                       ┬───────────────────────────
                                       ╰─ 🛑 A documented route must return JSONResponse<ConcreteType>; raw, opaque, streaming, and other response types are not inferred.
        @GET("other") @OpenAPIOperation("other")
        func other(req: Request) -> Other.JSONResponse<User> {}
                                 ┬──────────────────────────
                                 ╰─ 🛑 A documented route must return JSONResponse<ConcreteType>; raw, opaque, streaming, and other response types are not inferred.
      }
      """
    }
  }

  @Test func rejectsUnsupportedNativeForms() {
    assertMacro {
      """
      @OpenAPIController @Controller
      struct Routes {
        @HTTP(.get, "http") @OpenAPIOperation("http")
        func http(req: Request) -> JSONResponse<User> {}
        @HEAD("head") @OpenAPIOperation("head")
        func head(req: Request) -> JSONResponse<User> {}
        @OPTIONS("options") @OpenAPIOperation("options")
        func options(req: Request) -> JSONResponse<User> {}
        @GET(on: routes, "standalone") @OpenAPIOperation("standalone")
        func standalone(req: Request) -> JSONResponse<User> {}
        @VaporMacros.GET("qualified") @OpenAPIOperation("qualified")
        func qualified(req: Request) -> JSONResponse<User> {}
        @OpenAPIOperation("missing")
        func missing(req: Request) -> JSONResponse<User> {}
      }
      """
    } diagnostics: {
      """
      @OpenAPIController @Controller
      struct Routes {
        @HTTP(.get, "http") @OpenAPIOperation("http")
        ┬──────────────────
        ╰─ 🛑 Documented routes support only unqualified native @GET, @POST, @PUT, @PATCH, and @DELETE; @HTTP is unsupported.
        func http(req: Request) -> JSONResponse<User> {}
        @HEAD("head") @OpenAPIOperation("head")
        ┬────────────
        ╰─ 🛑 Documented routes support only unqualified native @GET, @POST, @PUT, @PATCH, and @DELETE; @HEAD is unsupported.
        func head(req: Request) -> JSONResponse<User> {}
        @OPTIONS("options") @OpenAPIOperation("options")
        ┬──────────────────
        ╰─ 🛑 Documented routes support only unqualified native @GET, @POST, @PUT, @PATCH, and @DELETE; @OPTIONS is unsupported.
        func options(req: Request) -> JSONResponse<User> {}
        @GET(on: routes, "standalone") @OpenAPIOperation("standalone")
             ┬──────────
             ╰─ 🛑 Documented controller routes do not support labeled or on: route arguments.
        func standalone(req: Request) -> JSONResponse<User> {}
        @VaporMacros.GET("qualified") @OpenAPIOperation("qualified")
        ┬────────────────────────────
        ╰─ 🛑 Documented routes support only unqualified native @GET, @POST, @PUT, @PATCH, and @DELETE; @VaporMacros.GET is unsupported.
        func qualified(req: Request) -> JSONResponse<User> {}
        @OpenAPIOperation("missing")
        func missing(req: Request) -> JSONResponse<User> {}
             ┬──────
             ╰─ 🛑 A documented route requires exactly one native @GET, @POST, @PUT, @PATCH, or @DELETE.
      }
      """
    }
  }

  @Test func rejectsMissingAndDuplicateOperationMarkers() {
    assertMacro {
      """
      @Controller @OpenAPIController
      struct Routes {
        @GET("query") @OpenAPIQuery("q", String.self)
        func query(req: Request) -> JSONResponse<User> {}
        @POST("body") @OpenAPIRequestBody(User.self)
        func body(req: Request) -> JSONResponse<User> {}
        @GET("duplicate") @OpenAPIOperation("a") @OpenAPIOperation("b")
        func duplicate(req: Request) -> JSONResponse<User> {}
        @GET("two") @POST("two") @OpenAPIOperation("two")
        func two(req: Request) -> JSONResponse<User> {}
      }
      """
    } diagnostics: {
      """
      @Controller @OpenAPIController
      struct Routes {
        @GET("query") @OpenAPIQuery("q", String.self)
        func query(req: Request) -> JSONResponse<User> {}
             ┬────
             ╰─ 🛑 A documented route requires exactly one @OpenAPIOperation.
        @POST("body") @OpenAPIRequestBody(User.self)
        func body(req: Request) -> JSONResponse<User> {}
             ┬───
             ╰─ 🛑 A documented route requires exactly one @OpenAPIOperation.
        @GET("duplicate") @OpenAPIOperation("a") @OpenAPIOperation("b")
        func duplicate(req: Request) -> JSONResponse<User> {}
             ┬────────
             ╰─ 🛑 A documented route requires exactly one @OpenAPIOperation.
        @GET("two") @POST("two") @OpenAPIOperation("two")
        func two(req: Request) -> JSONResponse<User> {}
             ┬──
             ╰─ 🛑 A documented route requires exactly one native @GET, @POST, @PUT, @PATCH, or @DELETE.
      }
      """
    }
  }

  @Test func rejectsDuplicateIDsAndNormalizedRoutes() {
    assertMacro {
      """
      @Controller @OpenAPIController
      struct Routes {
        @GET("users", Int.self) @OpenAPIOperation("first")
        func first(req: Request, id: Int) -> JSONResponse<User> {}
        @GET("other") @OpenAPIOperation("first")
        func duplicateID(req: Request) -> JSONResponse<User> {}
        @GET("users", String.self) @OpenAPIOperation("third")
        func duplicatePath(req: Request, id: String) -> JSONResponse<User> {}
      }
      """
    } diagnostics: {
      """
      @Controller @OpenAPIController
      struct Routes {
        @GET("users", Int.self) @OpenAPIOperation("first")
        func first(req: Request, id: Int) -> JSONResponse<User> {}
        @GET("other") @OpenAPIOperation("first")
        func duplicateID(req: Request) -> JSONResponse<User> {}
             ┬──────────
             ╰─ 🛑 Duplicate OpenAPI operation ID 'first'.
        @GET("users", String.self) @OpenAPIOperation("third")
        func duplicatePath(req: Request, id: String) -> JSONResponse<User> {}
             ┬────────────
             ╰─ 🛑 Duplicate documented route 'GET users/:string0'.
      }
      """
    }
  }

  @Test func allowsSamePathWithDifferentMethodsAndCaseSensitiveQueryNames() {
    assertMacro {
      """
      @Controller @OpenAPIController
      struct Routes {
        @GET("users") @OpenAPIOperation("get")
        @OpenAPIQuery("name", String.self)
        @OpenAPIQuery("Name", String.self)
        func get(req: Request) -> JSONResponse<User> {}
        @POST("users") @OpenAPIOperation("post")
        func post(req: Request) -> JSONResponse<User> {}
      }
      """
    } expansion: {
      """
      @Controller
      struct Routes {
        @GET("users")
        func get(req: Request) -> JSONResponse<User> {}
        @POST("users")
        func post(req: Request) -> JSONResponse<User> {}

        static var openAPIRoutes: [OpenAPISchemaVapor5.OpenAPIRouteDescriptor] {
          [
            OpenAPISchemaVapor5.OpenAPIRouteDescriptor(
              method: "GET",
              path: ["users"],
              operationID: "get",
              parameters: [.query("name", String.self, required: false), .query("Name", String.self, required: false)],
              requestBody: nil,
              responses: [.json(200, User.self)],
              security: .publicAccess
            ),
            OpenAPISchemaVapor5.OpenAPIRouteDescriptor(
              method: "POST",
              path: ["users"],
              operationID: "post",
              parameters: [],
              requestBody: nil,
              responses: [.json(200, User.self)],
              security: .publicAccess
            )
          ]
        }
      }

      extension Routes: OpenAPISchemaVapor5.OpenAPIControllerMetadata {
      }
      """
    }
  }

  @Test func rejectsDuplicateParametersAndSingletons() {
    assertMacro {
      """
      @Controller @OpenAPIController
      struct Routes {
        @GET("q") @OpenAPIOperation("q")
        @OpenAPIQuery("name", String.self) @OpenAPIQuery("name", Int.self)
        func query(req: Request) -> JSONResponse<User> {}
        @GET("h") @OpenAPIOperation("h")
        @OpenAPIHeader("X-Trace", String.self) @OpenAPIHeader("x-trace", String.self)
        func header(req: Request) -> JSONResponse<User> {}
        @POST("b") @OpenAPIOperation("b")
        @OpenAPIRequestBody(User.self) @OpenAPIRequestBody(User.self)
        func body(req: Request) -> JSONResponse<User> {}
        @GET("s") @OpenAPIOperation("s")
        @OpenAPISecurity("one") @OpenAPISecurity("two")
        func security(req: Request) -> JSONResponse<User> {}
        @GET("e") @OpenAPIOperation("e")
        @OpenAPIError(404, User.self) @OpenAPIError(404, Other.self)
        func error(req: Request) -> JSONResponse<User> {}
      }
      """
    } diagnostics: {
      """
      @Controller @OpenAPIController
      struct Routes {
        @GET("q") @OpenAPIOperation("q")
        @OpenAPIQuery("name", String.self) @OpenAPIQuery("name", Int.self)
                                           ┬──────────────────────────────
                                           ╰─ 🛑 Duplicate query parameter 'name'.
        func query(req: Request) -> JSONResponse<User> {}
        @GET("h") @OpenAPIOperation("h")
        @OpenAPIHeader("X-Trace", String.self) @OpenAPIHeader("x-trace", String.self)
                                               ┬─────────────────────────────────────
                                               ╰─ 🛑 Duplicate header parameter 'x-trace'.
        func header(req: Request) -> JSONResponse<User> {}
        @POST("b") @OpenAPIOperation("b")
        @OpenAPIRequestBody(User.self) @OpenAPIRequestBody(User.self)
                                       ┬─────────────────────────────
                                       ╰─ 🛑 Use @OpenAPIRequestBody only once per route.
        func body(req: Request) -> JSONResponse<User> {}
        @GET("s") @OpenAPIOperation("s")
        @OpenAPISecurity("one") @OpenAPISecurity("two")
                                ┬──────────────────────
                                ╰─ 🛑 Use @OpenAPISecurity only once per route.
        func security(req: Request) -> JSONResponse<User> {}
        @GET("e") @OpenAPIOperation("e")
        @OpenAPIError(404, User.self) @OpenAPIError(404, Other.self)
                                      ┬─────────────────────────────
                                      ╰─ 🛑 Duplicate response status 404.
        func error(req: Request) -> JSONResponse<User> {}
      }
      """
    }
  }

  @Test func rejectsUnsafePathLiterals() {
    assertMacro {
      #"""
      @Controller @OpenAPIController
      struct Routes {
        @GET("users/all") @OpenAPIOperation("multisegment")
        func multisegment(req: Request) -> JSONResponse<User> {}
        @GET(":id") @OpenAPIOperation("manual")
        func manual(req: Request) -> JSONResponse<User> {}
        @GET("*") @OpenAPIOperation("wildcard")
        func wildcard(req: Request) -> JSONResponse<User> {}
        @GET("users\(suffix)") @OpenAPIOperation("interpolated")
        func interpolated(req: Request) -> JSONResponse<User> {}
        @GET("escaped\n") @OpenAPIOperation("escaped")
        func escaped(req: Request) -> JSONResponse<User> {}
        @GET("") @OpenAPIOperation("empty")
        func empty(req: Request) -> JSONResponse<User> {}
      }
      """#
    } diagnostics: {
      #"""
      @Controller @OpenAPIController
      struct Routes {
        @GET("users/all") @OpenAPIOperation("multisegment")
             ┬──────────
             ╰─ 🛑 Use one literal segment per argument; manual captures, aliases, and wildcards are unsupported. Use Int.self, String.self, or another supported primitive for captures.
        func multisegment(req: Request) -> JSONResponse<User> {}
        @GET(":id") @OpenAPIOperation("manual")
             ┬────
             ╰─ 🛑 Use one literal segment per argument; manual captures, aliases, and wildcards are unsupported. Use Int.self, String.self, or another supported primitive for captures.
        func manual(req: Request) -> JSONResponse<User> {}
        @GET("*") @OpenAPIOperation("wildcard")
             ┬──
             ╰─ 🛑 Use one literal segment per argument; manual captures, aliases, and wildcards are unsupported. Use Int.self, String.self, or another supported primitive for captures.
        func wildcard(req: Request) -> JSONResponse<User> {}
        @GET("users\(suffix)") @OpenAPIOperation("interpolated")
             ┬───────────────
             ╰─ 🛑 Route segment must be a nonempty plain string literal without interpolation or escapes.
        func interpolated(req: Request) -> JSONResponse<User> {}
        @GET("escaped\n") @OpenAPIOperation("escaped")
             ┬──────────
             ╰─ 🛑 Route segment must be a nonempty plain string literal without interpolation or escapes.
        func escaped(req: Request) -> JSONResponse<User> {}
        @GET("") @OpenAPIOperation("empty")
             ┬─
             ╰─ 🛑 Route segment must be a nonempty plain string literal without interpolation or escapes.
        func empty(req: Request) -> JSONResponse<User> {}
      }
      """#
    }
  }

  @Test func rejectsUnsafePathTypesAndExpressions() {
    assertMacro {
      """
      @Controller @OpenAPIController
      struct Routes {
        @GET(Foundation.UUID.self) @OpenAPIOperation("qualified")
        func qualified(req: Request, id: UUID) -> JSONResponse<User> {}
        @GET(Int?.self) @OpenAPIOperation("optional")
        func optional(req: Request, id: Int?) -> JSONResponse<User> {}
        @GET(UserID.self) @OpenAPIOperation("custom")
        func custom(req: Request, id: UserID) -> JSONResponse<User> {}
        @GET(["users"]) @OpenAPIOperation("array")
        func array(req: Request) -> JSONResponse<User> {}
        @GET(path) @OpenAPIOperation("variable")
        func variable(req: Request) -> JSONResponse<User> {}
        @GET(Int.self, required: false) @OpenAPIOperation("required")
        func required(req: Request, id: Int) -> JSONResponse<User> {}
      }
      """
    } diagnostics: {
      """
      @Controller @OpenAPIController
      struct Routes {
        @GET(Foundation.UUID.self) @OpenAPIOperation("qualified")
             ┬───────────────────
             ╰─ 🛑 Path types must be unqualified supported primitives (for example Int.self, String.self, UUID.self); optional, qualified, and custom path types are unsupported.
        func qualified(req: Request, id: UUID) -> JSONResponse<User> {}
        @GET(Int?.self) @OpenAPIOperation("optional")
             ┬────────
             ╰─ 🛑 Path types must be unqualified supported primitives (for example Int.self, String.self, UUID.self); optional, qualified, and custom path types are unsupported.
        func optional(req: Request, id: Int?) -> JSONResponse<User> {}
        @GET(UserID.self) @OpenAPIOperation("custom")
             ┬──────────
             ╰─ 🛑 Path types must be unqualified supported primitives (for example Int.self, String.self, UUID.self); optional, qualified, and custom path types are unsupported.
        func custom(req: Request, id: UserID) -> JSONResponse<User> {}
        @GET(["users"]) @OpenAPIOperation("array")
             ┬────────
             ╰─ 🛑 Expected an explicit concrete type reference such as Model.self.
        func array(req: Request) -> JSONResponse<User> {}
        @GET(path) @OpenAPIOperation("variable")
             ┬───
             ╰─ 🛑 Expected an explicit concrete type reference such as Model.self.
        func variable(req: Request) -> JSONResponse<User> {}
        @GET(Int.self, required: false) @OpenAPIOperation("required")
                       ┬──────────────
                       ╰─ 🛑 Documented controller routes do not support labeled or on: route arguments.
        func required(req: Request, id: Int) -> JSONResponse<User> {}
      }
      """
    }
  }

  @Test func rejectsMalformedMarkerArguments() {
    assertMacro {
      """
      @Controller @OpenAPIController
      struct Routes {
        @GET("operation") @OpenAPIOperation("operation", summary: "no")
        func operation(req: Request) -> JSONResponse<User> {}
        @GET("arity") @OpenAPIOperation()
        func arity(req: Request) -> JSONResponse<User> {}
        @GET("query") @OpenAPIOperation("query") @OpenAPIQuery("name", String.self, required: flag)
        func query(req: Request) -> JSONResponse<User> {}
        @GET("header") @OpenAPIOperation("header") @OpenAPIHeader("X", String.self, extra: true)
        func header(req: Request) -> JSONResponse<User> {}
        @POST("body") @OpenAPIOperation("body") @OpenAPIRequestBody(User)
        func body(req: Request) -> JSONResponse<User> {}
        @GET("error") @OpenAPIOperation("error") @OpenAPIError(404)
        func error(req: Request) -> JSONResponse<User> {}
        @GET("security") @OpenAPIOperation("security") @OpenAPISecurity("bearer", optional: "yes")
        func security(req: Request) -> JSONResponse<User> {}
        @GET("securityLabel") @OpenAPIOperation("securityLabel") @OpenAPISecurity("bearer", scopes: [])
        func securityLabel(req: Request) -> JSONResponse<User> {}
      }
      """
    } diagnostics: {
      """
      @Controller @OpenAPIController
      struct Routes {
        @GET("operation") @OpenAPIOperation("operation", summary: "no")
                                                         ┬────────────
                                                         ╰─ 🛑 Unknown or duplicate @OpenAPIOperation argument label 'summary'.
        func operation(req: Request) -> JSONResponse<User> {}
        @GET("arity") @OpenAPIOperation()
                      ┬──────────────────
                      ╰─ 🛑 @OpenAPIOperation requires 1 positional argument(s).
        func arity(req: Request) -> JSONResponse<User> {}
        @GET("query") @OpenAPIOperation("query") @OpenAPIQuery("name", String.self, required: flag)
                                                                                              ┬───
                                                                                              ╰─ 🛑 Expected a literal true or false.
        func query(req: Request) -> JSONResponse<User> {}
        @GET("header") @OpenAPIOperation("header") @OpenAPIHeader("X", String.self, extra: true)
                                                                                    ┬──────────
                                                                                    ╰─ 🛑 Unknown or duplicate @OpenAPIHeader argument label 'extra'.
        func header(req: Request) -> JSONResponse<User> {}
        @POST("body") @OpenAPIOperation("body") @OpenAPIRequestBody(User)
                                                                    ┬───
                                                                    ╰─ 🛑 Expected an explicit concrete type reference such as Model.self.
        func body(req: Request) -> JSONResponse<User> {}
        @GET("error") @OpenAPIOperation("error") @OpenAPIError(404)
                                                 ┬─────────────────
                                                 ╰─ 🛑 @OpenAPIError requires 2 positional argument(s).
        func error(req: Request) -> JSONResponse<User> {}
        @GET("security") @OpenAPIOperation("security") @OpenAPISecurity("bearer", optional: "yes")
                                                                                            ┬────
                                                                                            ╰─ 🛑 Expected a literal true or false.
        func security(req: Request) -> JSONResponse<User> {}
        @GET("securityLabel") @OpenAPIOperation("securityLabel") @OpenAPISecurity("bearer", scopes: [])
                                                                                            ┬─────────
                                                                                            ╰─ 🛑 Unknown or duplicate @OpenAPISecurity argument label 'scopes'.
        func securityLabel(req: Request) -> JSONResponse<User> {}
      }
      """
    }
  }

  @Test func rejectsMalformedStringsAndTypeReferences() {
    assertMacro {
      #"""
      @Controller @OpenAPIController
      struct Routes {
        @GET("id") @OpenAPIOperation("get\(name)")
        func id(req: Request) -> JSONResponse<User> {}
        @GET("q") @OpenAPIOperation("q") @OpenAPIQuery("", String.self)
        func query(req: Request) -> JSONResponse<User> {}
        @GET("s") @OpenAPIOperation("s") @OpenAPISecurity(scheme)
        func security(req: Request) -> JSONResponse<User> {}
        @POST("b") @OpenAPIOperation("b") @OpenAPIRequestBody(makeType().self)
        func body(req: Request) -> JSONResponse<User> {}
        @GET("h") @OpenAPIOperation("h") @OpenAPIHeader("X", (any Schemable).self)
        func header(req: Request) -> JSONResponse<User> {}
      }
      """#
    } diagnostics: {
      #"""
      @Controller @OpenAPIController
      struct Routes {
        @GET("id") @OpenAPIOperation("get\(name)")
                                     ┬───────────
                                     ╰─ 🛑 Operation ID must be a nonempty plain string literal without interpolation or escapes.
        func id(req: Request) -> JSONResponse<User> {}
        @GET("q") @OpenAPIOperation("q") @OpenAPIQuery("", String.self)
                                                       ┬─
                                                       ╰─ 🛑 Parameter name must be a nonempty plain string literal without interpolation or escapes.
        func query(req: Request) -> JSONResponse<User> {}
        @GET("s") @OpenAPIOperation("s") @OpenAPISecurity(scheme)
                                                          ┬─────
                                                          ╰─ 🛑 Security scheme must be a nonempty plain string literal without interpolation or escapes.
        func security(req: Request) -> JSONResponse<User> {}
        @POST("b") @OpenAPIOperation("b") @OpenAPIRequestBody(makeType().self)
                                                              ┬──────────────
                                                              ╰─ 🛑 Expected an explicit concrete type reference such as Model.self.
        func body(req: Request) -> JSONResponse<User> {}
        @GET("h") @OpenAPIOperation("h") @OpenAPIHeader("X", (any Schemable).self)
                                                             ┬───────────────────
                                                             ╰─ 🛑 Expected an explicit concrete type reference such as Model.self.
        func header(req: Request) -> JSONResponse<User> {}
      }
      """#
    }
  }

  @Test func rejectsInvalidResponseStatuses() {
    assertMacro {
      """
      @Controller @OpenAPIController
      struct Routes {
        @GET("negative") @OpenAPIOperation("negative", status: -1)
        func negative(req: Request) -> JSONResponse<User> {}
        @GET("status") @OpenAPIOperation("status", status: code)
        func variable(req: Request) -> JSONResponse<User> {}
        @GET("string") @OpenAPIOperation("string", status: "201")
        func string(req: Request) -> JSONResponse<User> {}
        @GET("error") @OpenAPIOperation("error", status: 404)
        func error(req: Request) -> JSONResponse<User> {}
        @GET("noContent") @OpenAPIOperation("noContent", status: 204)
        func noContent(req: Request) -> JSONResponse<User> {}
        @GET("invalidError") @OpenAPIOperation("invalidError") @OpenAPIError(600, User.self)
        func invalidError(req: Request) -> JSONResponse<User> {}
        @GET("successError") @OpenAPIOperation("successError") @OpenAPIError(200, User.self)
        func successError(req: Request) -> JSONResponse<User> {}
      }
      """
    } diagnostics: {
      """
      @Controller @OpenAPIController
      struct Routes {
        @GET("negative") @OpenAPIOperation("negative", status: -1)
                                                               ┬─
                                                               ╰─ 🛑 Success status must be a decimal integer literal from 200 through 299.
        func negative(req: Request) -> JSONResponse<User> {}
        @GET("status") @OpenAPIOperation("status", status: code)
                                                           ┬───
                                                           ╰─ 🛑 Success status must be a decimal integer literal from 200 through 299.
        func variable(req: Request) -> JSONResponse<User> {}
        @GET("string") @OpenAPIOperation("string", status: "201")
                                                           ┬────
                                                           ╰─ 🛑 Success status must be a decimal integer literal from 200 through 299.
        func string(req: Request) -> JSONResponse<User> {}
        @GET("error") @OpenAPIOperation("error", status: 404)
                                                         ┬──
                                                         ╰─ 🛑 Success status must be a decimal integer literal from 200 through 299.
        func error(req: Request) -> JSONResponse<User> {}
        @GET("noContent") @OpenAPIOperation("noContent", status: 204)
                                                                 ┬──
                                                                 ╰─ 🛑 JSONResponse cannot document the bodyless HTTP status 204.
        func noContent(req: Request) -> JSONResponse<User> {}
        @GET("invalidError") @OpenAPIOperation("invalidError") @OpenAPIError(600, User.self)
                                                                             ┬──
                                                                             ╰─ 🛑 Error status must be a decimal integer literal from 400 through 599.
        func invalidError(req: Request) -> JSONResponse<User> {}
        @GET("successError") @OpenAPIOperation("successError") @OpenAPIError(200, User.self)
                                                                             ┬──
                                                                             ╰─ 🛑 Error status must be a decimal integer literal from 400 through 599.
        func successError(req: Request) -> JSONResponse<User> {}
      }
      """
    }
  }

  @Test func requiresExplicitSecurityAndConsistentOptionality() {
    assertMacro {
      """
      @Controller @OpenAPIController
      struct Routes {
        @GET("missing") @OpenAPIOperation("missing") @AuthMiddleware(User.self)
        func missing(req: Request, user: User) -> JSONResponse<User> {}
        @GET("optional") @OpenAPIOperation("optional")
        @AuthMiddleware(User.self) @OpenAPISecurity("bearer")
        func optional(req: Request, user: User?) -> JSONResponse<User> {}
        @GET("required") @OpenAPIOperation("required")
        @AuthMiddleware(User.self) @OpenAPISecurity("bearer", optional: true)
        func required(req: Request, user: User) -> JSONResponse<User> {}
        @GET("noParameter") @OpenAPIOperation("noParameter")
        @AuthMiddleware(User.self) @OpenAPISecurity("bearer")
        func noParameter(req: Request) -> JSONResponse<User> {}
      }
      """
    } diagnostics: {
      """
      @Controller @OpenAPIController
      struct Routes {
        @GET("missing") @OpenAPIOperation("missing") @AuthMiddleware(User.self)
                                                     ┬─────────────────────────
                                                     ╰─ 🛑 A documented @AuthMiddleware route requires explicit @OpenAPISecurity; schemes are never inferred from authentication types.
        func missing(req: Request, user: User) -> JSONResponse<User> {}
        @GET("optional") @OpenAPIOperation("optional")
        @AuthMiddleware(User.self) @OpenAPISecurity("bearer")
        ┬─────────────────────────
        ╰─ 🛑 @OpenAPISecurity optional: must match the native authentication parameter's optionality.
        func optional(req: Request, user: User?) -> JSONResponse<User> {}
        @GET("required") @OpenAPIOperation("required")
        @AuthMiddleware(User.self) @OpenAPISecurity("bearer", optional: true)
        ┬─────────────────────────
        ╰─ 🛑 @OpenAPISecurity optional: must match the native authentication parameter's optionality.
        func required(req: Request, user: User) -> JSONResponse<User> {}
        @GET("noParameter") @OpenAPIOperation("noParameter")
        @AuthMiddleware(User.self) @OpenAPISecurity("bearer")
        ┬─────────────────────────
        ╰─ 🛑 No handler parameter matches authentication type 'User'.
        func noParameter(req: Request) -> JSONResponse<User> {}
      }
      """
    }
  }

  @Test func rejectsOrphanMarkersAndWrongDeclarations() {
    assertMacro {
      """
      @OpenAPIOperation("orphan")
      func orphan(req: Request) -> JSONResponse<User> {}
      @OpenAPIRequestBody(User.self)
      struct NotAFunction {}
      @OpenAPIQuery("q", String.self)
      var value = ""
      @OpenAPIHeader("X", String.self)
      func header(req: Request) -> JSONResponse<User> {}
      @OpenAPIError(404, User.self)
      func error(req: Request) -> JSONResponse<User> {}
      @OpenAPISecurity("bearer")
      func security(req: Request) -> JSONResponse<User> {}
      """
    } diagnostics: {
      """
      @OpenAPIOperation("orphan")
      ┬──────────────────────────
      ╰─ 🛑 @OpenAPIOperation requires a direct member of an @OpenAPIController type.
      func orphan(req: Request) -> JSONResponse<User> {}
      @OpenAPIRequestBody(User.self)
      ┬─────────────────────────────
      ╰─ 🛑 @OpenAPIRequestBody can only be attached to a route function.
      struct NotAFunction {}
      @OpenAPIQuery("q", String.self)
      ┬──────────────────────────────
      ╰─ 🛑 @OpenAPIQuery can only be attached to a route function.
      var value = ""
      @OpenAPIHeader("X", String.self)
      ┬───────────────────────────────
      ╰─ 🛑 @OpenAPIHeader requires a direct member of an @OpenAPIController type.
      func header(req: Request) -> JSONResponse<User> {}
      @OpenAPIError(404, User.self)
      ┬────────────────────────────
      ╰─ 🛑 @OpenAPIError requires a direct member of an @OpenAPIController type.
      func error(req: Request) -> JSONResponse<User> {}
      @OpenAPISecurity("bearer")
      ┬─────────────────────────
      ╰─ 🛑 @OpenAPISecurity requires a direct member of an @OpenAPIController type.
      func security(req: Request) -> JSONResponse<User> {}
      """
    }
  }

  @Test func rejectsNestedAndFreestandingContexts() {
    assertMacro {
      """
      @Controller @OpenAPIController
      struct Outer {
        struct Nested {
          @GET("nested") @OpenAPIOperation("nested")
          func nested(req: Request) -> JSONResponse<User> {}
        }
        func register(routes: any RoutesBuilder) {
          @OpenAPIOperation("local")
          func local(req: Request) -> JSONResponse<User> {}
        }
        @OpenAPIOperation("freestanding")
        #GET(on: routes, "free", handler: handler)
      }
      """
    } diagnostics: {
      """
      @Controller @OpenAPIController
      struct Outer {
        struct Nested {
          @GET("nested") @OpenAPIOperation("nested")
                         ┬──────────────────────────
                         ╰─ 🛑 @OpenAPIOperation requires a direct member of an @OpenAPIController type.
          func nested(req: Request) -> JSONResponse<User> {}
        }
        func register(routes: any RoutesBuilder) {
          @OpenAPIOperation("local")
          ┬─────────────────────────
          ╰─ 🛑 @OpenAPIOperation requires a direct member of an @OpenAPIController type.
          func local(req: Request) -> JSONResponse<User> {}
        }
        @OpenAPIOperation("freestanding")
        ┬────────────────────────────────
        ╰─ 🛑 @OpenAPIOperation can only be attached to a route function.
        #GET(on: routes, "free", handler: handler)
      }
      """
    }
  }

  @Test func rejectsReservedPropertyAndInvalidController() {
    assertMacro {
      """
      @Controller @OpenAPIController
      struct Conflict {
        static var openAPIRoutes: [OpenAPIRouteDescriptor] { [] }
      }
      @OpenAPIController
      struct MissingController {}
      @Controller @OpenAPIController(extra: true)
      struct ExtraArgument {}
      @Controller @OpenAPIController
      actor Unsupported {}
      """
    } diagnostics: {
      """
      @Controller @OpenAPIController
      struct Conflict {
        static var openAPIRoutes: [OpenAPIRouteDescriptor] { [] }
        ┬────────────────────────────────────────────────────────
        ╰─ 🛑 'openAPIRoutes' is reserved for @OpenAPIController metadata.
      }
      @OpenAPIController
      ┬─────────────────
      ╰─ 🛑 @OpenAPIController must accompany native Vapor @Controller.
      struct MissingController {}
      @Controller @OpenAPIController(extra: true)
                                     ┬──────────
                                     ╰─ 🛑 Unknown or duplicate @OpenAPIController argument label 'extra'.
      struct ExtraArgument {}
      @Controller @OpenAPIController
                  ┬─────────────────
                  ╰─ 🛑 @OpenAPIController requires a struct, class, or enum declaration.
      actor Unsupported {}
      """
    }
  }

  @Test func supportsClassAndPackageAccess() {
    assertMacro {
      """
      @Controller @OpenAPIController
      package final class Routes {
        @GET("test") @OpenAPIOperation("test")
        func test(req: Request) -> JSONResponse<User> {}
      }
      """
    } expansion: {
      """
      @Controller
      package final class Routes {
        @GET("test")
        func test(req: Request) -> JSONResponse<User> {}

        package static var openAPIRoutes: [OpenAPISchemaVapor5.OpenAPIRouteDescriptor] {
          [
            OpenAPISchemaVapor5.OpenAPIRouteDescriptor(
              method: "GET",
              path: ["test"],
              operationID: "test",
              parameters: [],
              requestBody: nil,
              responses: [.json(200, User.self)],
              security: .publicAccess
            )
          ]
        }
      }

      extension Routes: OpenAPISchemaVapor5.OpenAPIControllerMetadata {
      }
      """
    }
  }

  @Test func rejectsNoncanonicalNativeTypeSpelling() {
    assertMacro {
      """
      @Controller @OpenAPIController
      struct Routes {
        @GET(Int .self) @OpenAPIOperation("space")
        func space(req: Request, id: Int) -> JSONResponse<User> {}
        @GET(Int /* capture */ .self) @OpenAPIOperation("comment")
        func comment(req: Request, id: Int) -> JSONResponse<User> {}
        @GET("auth") @OpenAPIOperation("auth")
        @AuthMiddleware(User .self) @OpenAPISecurity("bearer")
        func auth(req: Request, user: User) -> JSONResponse<User> {}
        @GET("qualified") @OpenAPIOperation("qualified")
        @VaporMacros.AuthMiddleware(User.self) @OpenAPISecurity("bearer")
        func qualified(req: Request, user: User) -> JSONResponse<User> {}
      }
      """
    } diagnostics: {
      """
      @Controller @OpenAPIController
      struct Routes {
        @GET(Int .self) @OpenAPIOperation("space")
             ┬────────
             ╰─ 🛑 Use canonical Int.self spelling without internal whitespace or comments to match native capture names.
        func space(req: Request, id: Int) -> JSONResponse<User> {}
        @GET(Int /* capture */ .self) @OpenAPIOperation("comment")
             ┬──────────────────────
             ╰─ 🛑 Use canonical Int.self spelling without internal whitespace or comments to match native capture names.
        func comment(req: Request, id: Int) -> JSONResponse<User> {}
        @GET("auth") @OpenAPIOperation("auth")
        @AuthMiddleware(User .self) @OpenAPISecurity("bearer")
                        ┬─────────
                        ╰─ 🛑 Use canonical User.self spelling for native authentication.
        func auth(req: Request, user: User) -> JSONResponse<User> {}
        @GET("qualified") @OpenAPIOperation("qualified")
        @VaporMacros.AuthMiddleware(User.self) @OpenAPISecurity("bearer")
        ┬─────────────────────────────────────
        ╰─ 🛑 Use unqualified native @AuthMiddleware on documented routes.
        func qualified(req: Request, user: User) -> JSONResponse<User> {}
      }
      """
    }
  }

  @Test func rejectsConditionalRoutesAndGenericHandlers() {
    assertMacro {
      """
      @Controller @OpenAPIController
      struct Conditional {
        #if FEATURE
        @GET("feature") @OpenAPIOperation("feature")
        func feature(req: Request) -> JSONResponse<User> {}
        #endif
      }
      @Controller @OpenAPIController
      struct Generic {
        @GET("generic") @OpenAPIOperation("generic")
        func generic<T: Codable & Schemable>(req: Request) -> JSONResponse<T> {}
      }
      """
    } diagnostics: {
      """
      @Controller @OpenAPIController
      struct Conditional {
        #if FEATURE
        @GET("feature") @OpenAPIOperation("feature")
                        ┬───────────────────────────
                        ╰─ 🛑 Documented routes inside conditional compilation are unsupported by native @Controller.
        func feature(req: Request) -> JSONResponse<User> {}
        #endif
      }
      @Controller @OpenAPIController
      struct Generic {
        @GET("generic") @OpenAPIOperation("generic")
        func generic<T: Codable & Schemable>(req: Request) -> JSONResponse<T> {}
             ┬──────
             ╰─ 🛑 Documented route handlers cannot be generic functions.
      }
      """
    }
  }

  @Test func rejectsOtherReservedNames() {
    assertMacro {
      """
      @Controller @OpenAPIController
      struct FunctionConflict {
        static func openAPIRoutes() {}
      }
      @Controller @OpenAPIController
      struct AliasConflict {
        typealias openAPIRoutes = String
      }
      @Controller @OpenAPIController
      enum CaseConflict {
        case openAPIRoutes
      }
      """
    } diagnostics: {
      """
      @Controller @OpenAPIController
      struct FunctionConflict {
        static func openAPIRoutes() {}
        ┬─────────────────────────────
        ╰─ 🛑 'openAPIRoutes' is reserved for @OpenAPIController metadata.
      }
      @Controller @OpenAPIController
      struct AliasConflict {
        typealias openAPIRoutes = String
        ┬───────────────────────────────
        ╰─ 🛑 'openAPIRoutes' is reserved for @OpenAPIController metadata.
      }
      @Controller @OpenAPIController
      enum CaseConflict {
        case openAPIRoutes
        ┬─────────────────
        ╰─ 🛑 'openAPIRoutes' is reserved for @OpenAPIController metadata.
      }
      """
    }
  }

  @Test func rejectsDuplicateLabelsAndInvalidMetatypes() {
    assertMacro {
      """
      @Controller @OpenAPIController
      struct Routes {
        @GET("labels") @OpenAPIOperation("labels", status: 200, status: 201)
        func labels(req: Request) -> JSONResponse<User> {}
        @GET("order") @OpenAPIOperation(status: 200, "order")
        func order(req: Request) -> JSONResponse<User> {}
        @GET("query") @OpenAPIOperation("query") @OpenAPIQuery("q", typeVariable)
        func query(req: Request) -> JSONResponse<User> {}
        @POST("body") @OpenAPIOperation("body") @OpenAPIRequestBody(User.self, required: false)
        func body(req: Request) -> JSONResponse<User> {}
        @GET("error") @OpenAPIOperation("error") @OpenAPIError(404, User.self, description: "missing")
        func error(req: Request) -> JSONResponse<User> {}
      }
      """
    } diagnostics: {
      """
      @Controller @OpenAPIController
      struct Routes {
        @GET("labels") @OpenAPIOperation("labels", status: 200, status: 201)
                                                                ┬──────────
                                                                ╰─ 🛑 Unknown or duplicate @OpenAPIOperation argument label 'status'.
        func labels(req: Request) -> JSONResponse<User> {}
        @GET("order") @OpenAPIOperation(status: 200, "order")
                                                     ┬──────
                                                     ╰─ 🛑 Positional arguments must precede labeled arguments.
        func order(req: Request) -> JSONResponse<User> {}
        @GET("query") @OpenAPIOperation("query") @OpenAPIQuery("q", typeVariable)
                                                                    ┬───────────
                                                                    ╰─ 🛑 Expected an explicit concrete type reference such as Model.self.
        func query(req: Request) -> JSONResponse<User> {}
        @POST("body") @OpenAPIOperation("body") @OpenAPIRequestBody(User.self, required: false)
                                                                               ┬──────────────
                                                                               ╰─ 🛑 Unknown or duplicate @OpenAPIRequestBody argument label 'required'.
        func body(req: Request) -> JSONResponse<User> {}
        @GET("error") @OpenAPIOperation("error") @OpenAPIError(404, User.self, description: "missing")
                                                                               ┬─────────────────────
                                                                               ╰─ 🛑 Unknown or duplicate @OpenAPIError argument label 'description'.
        func error(req: Request) -> JSONResponse<User> {}
      }
      """
    }
  }

  @Test func rejectsConditionalMarkerAttributes() {
    assertMacro {
      """
      @Controller @OpenAPIController
      struct Routes {
        #if FEATURE
        @OpenAPIOperation("conditional")
        #endif
        @GET("conditional")
        func conditional(req: Request) -> JSONResponse<User> {}
      }
      """
    } diagnostics: {
      """
      @Controller @OpenAPIController
      struct Routes {
        #if FEATURE
        @OpenAPIOperation("conditional")
        ┬───────────────────────────────
        ╰─ 🛑 Conditional OpenAPI annotations are unsupported; annotate the route directly.
        #endif
        @GET("conditional")
        func conditional(req: Request) -> JSONResponse<User> {}
      }
      """
    }
  }

  @Test func schemaConstraintsRemainInGeneratedGenericCalls() {
    assertMacro {
      """
      @Controller @OpenAPIController
      struct Routes {
        @GET(Int.self, String.self, Double.self, Bool.self, UUID.self)
        @OpenAPIOperation("schema")
        @OpenAPIRequestBody(NeedsCodableAndSchemable.self)
        @OpenAPIQuery("filter", NeedsOpenAPIParameterValue.self)
        @OpenAPIError(500, AlsoNeedsCodableAndSchemable.self)
        @OpenAPISecurity("declaredWithoutNativeAuth", optional: false)
        func schema(req: Request, id: Int, name: String, fraction: Double, flag: Bool, uuid: UUID) -> JSONResponse<NeedsCodableSchemableAndSendable> {}
      }
      """
    } expansion: {
      """
      @Controller
      struct Routes {
        @GET(Int.self, String.self, Double.self, Bool.self, UUID.self)
        func schema(req: Request, id: Int, name: String, fraction: Double, flag: Bool, uuid: UUID) -> JSONResponse<NeedsCodableSchemableAndSendable> {}

        static var openAPIRoutes: [OpenAPISchemaVapor5.OpenAPIRouteDescriptor] {
          [
            OpenAPISchemaVapor5.OpenAPIRouteDescriptor(
              method: "GET",
              path: [":int0", ":string1", ":double2", ":bool3", ":uuid4"],
              operationID: "schema",
              parameters: [.path("int0", Int.self), .path("string1", String.self), .path("double2", Double.self), .path("bool3", Bool.self), .path("uuid4", UUID.self), .query("filter", NeedsOpenAPIParameterValue.self, required: false)],
              requestBody: .json(NeedsCodableAndSchemable.self),
              responses: [.json(200, NeedsCodableSchemableAndSendable.self), .json(500, AlsoNeedsCodableAndSchemable.self)],
              security: .required("declaredWithoutNativeAuth")
            )
          ]
        }
      }

      extension Routes: OpenAPISchemaVapor5.OpenAPIControllerMetadata {
      }
      """
    }
  }

  @Test func rejectsPathScalarsWithoutRuntimeSupport() {
    assertMacro {
      """
      @Controller @OpenAPIController
      struct Routes {
        @GET(UInt8.self) @OpenAPIOperation("byte")
        func byte(req: Request, id: UInt8) -> JSONResponse<User> {}
        @GET(Float.self) @OpenAPIOperation("float")
        func float(req: Request, id: Float) -> JSONResponse<User> {}
      }
      """
    } diagnostics: {
      """
      @Controller @OpenAPIController
      struct Routes {
        @GET(UInt8.self) @OpenAPIOperation("byte")
             ┬─────────
             ╰─ 🛑 Path types must be unqualified supported primitives (for example Int.self, String.self, UUID.self); optional, qualified, and custom path types are unsupported.
        func byte(req: Request, id: UInt8) -> JSONResponse<User> {}
        @GET(Float.self) @OpenAPIOperation("float")
             ┬─────────
             ╰─ 🛑 Path types must be unqualified supported primitives (for example Int.self, String.self, UUID.self); optional, qualified, and custom path types are unsupported.
        func float(req: Request, id: Float) -> JSONResponse<User> {}
      }
      """
    }
  }
}
#endif