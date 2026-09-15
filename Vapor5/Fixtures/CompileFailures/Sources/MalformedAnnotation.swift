import JSONSchemaBuilder
import OpenAPISchemaVapor5
import OpenAPIVaporMacros
import Vapor
import VaporMacros

@Schemable struct Output: Content { let name: String }

@Controller
@OpenAPIController
struct InvalidController {
  @GET("items")
  @OpenAPIOperation("list", status: 99)
  func list(req: Request) async throws -> JSONResponse<Output> {
    JSONResponse(Output(name: "x"))
  }
}

@main enum Main { static func main() {} }
