import JSONSchemaBuilder
import OpenAPISchemaVapor5
import OpenAPIVaporMacros
import Vapor
import VaporMacros

struct Input: Codable { let name: String }
@Schemable struct Output: Content { let name: String }

@Controller
@OpenAPIController
struct InvalidController {
  @POST("items")
  @OpenAPIOperation("create")
  @OpenAPIRequestBody(Input.self)
  func create(req: Request) async throws -> JSONResponse<Output> {
    JSONResponse(Output(name: "x"))
  }
}

@main enum Main { static func main() {} }
