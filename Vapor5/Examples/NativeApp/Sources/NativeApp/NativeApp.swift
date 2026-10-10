import Foundation
import JSONSchemaBuilder
import Logging
import struct OpenAPISchema.Info
import OpenAPISchemaVapor5
import OpenAPIVaporMacros
import Vapor
import VaporMacros

@Schemable
struct CreatePet: Content {
  let name: String
}

@Schemable
struct Pet: Content {
  let id: Int
  let name: String
}

@Controller
@OpenAPIController
struct PetsController {
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

@main
enum NativeApp {
  static func main() async throws {
    let app = try await Application(.development)
    do {
      let registry = OpenAPIRegistry(application: app, info: Info(title: "Pets", version: "1.0.0"))
      try await registry.register(PetsController(), at: ["api", "v1"])
      let document = try registry.encodeCanonicalJSON()
      if CommandLine.arguments.contains("--print-spec") {
        FileHandle.standardOutput.write(document)
      } else {
        try await app.run()
      }
    } catch {
      do { try await app.shutdown() }
      catch { Logger.current.error("Shutdown failed: \(error)") }
      throw error
    }
    try await app.shutdown()
  }
}
