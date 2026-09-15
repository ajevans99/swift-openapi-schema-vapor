import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct OpenAPIVaporPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    OpenAPIControllerMacro.self,
    OpenAPIMarkerMacro.self,
  ]
}