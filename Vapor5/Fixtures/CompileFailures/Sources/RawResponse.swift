import OpenAPISchemaVapor5
import OpenAPIVaporMacros
import Vapor
import VaporMacros

@Controller
@OpenAPIController
struct InvalidController {
  @GET("stream")
  @OpenAPIOperation("stream")
  func stream(req: Request) async throws -> Response {
    Response(body: .init(stream: { writer in try await writer.write("chunk") }))
  }
}

@main enum Main { static func main() {} }
