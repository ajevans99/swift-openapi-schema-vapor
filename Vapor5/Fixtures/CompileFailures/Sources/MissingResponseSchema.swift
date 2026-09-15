import OpenAPISchemaVapor5
import OpenAPIVaporMacros
import Vapor
import VaporMacros

struct Output: Codable, Sendable { let name: String }

@Controller
@OpenAPIController
struct InvalidController {
  @GET("items")
  @OpenAPIOperation("list")
  func list(req: Request) async throws -> JSONResponse<Output> {
    JSONResponse(Output(name: "x"))
  }
}

@main enum Main { static func main() {} }
