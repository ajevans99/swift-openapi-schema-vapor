import OpenAPISchemaVapor5
import OpenAPIVaporMacros
import Vapor
import VaporMacros

@Controller
@OpenAPIController
struct InvalidController {
  @GET("items")
  @OpenAPIOperation("list")
  func list(req: Request) async throws -> some ResponseEncodable { "opaque" }
}

@main enum Main { static func main() {} }
