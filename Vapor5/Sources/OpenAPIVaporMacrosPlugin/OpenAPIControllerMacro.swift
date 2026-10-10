import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct OpenAPIControllerMacro: MemberMacro, ExtensionMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    do {
      try validateController(node, declaration)
      var descriptors: [String] = []
      var operationIDs: Set<String> = []
      var routes: Set<String> = []
      var invalid = false

      for member in declaration.memberBlock.members {
        guard let function = member.decl.as(FunctionDeclSyntax.self),
          attributes(function.attributes).contains(where: { markerNames.contains(name($0)) })
        else { continue }

        do {
          let route = try documentedRoute(function)
          guard operationIDs.insert(route.operationID).inserted else {
            throw Failure(function.name, "Duplicate OpenAPI operation ID '\(route.operationID)'.")
          }
          guard routes.insert(route.identity).inserted else {
            throw Failure(
              function.name,
              "Duplicate documented route '\(route.method) \(route.path.joined(separator: "/"))'."
            )
          }
          descriptors.append(route.expression)
        } catch let error as Failure {
          context.diagnose(error.diagnostic)
          invalid = true
        }
      }

      guard !invalid else { return [] }
      let access = declaration.modifiers.contains { ["public", "open"].contains($0.name.text) }
        ? "public " : declaration.modifiers.contains { $0.name.text == "package" } ? "package " : ""
      let entries = descriptors.joined(separator: ",\n")
      let array = descriptors.isEmpty ? "[]" : "[\n\(entries)\n]"
      return [
        """
        \(raw: access)static var openAPIRoutes: [OpenAPISchemaVapor5.OpenAPIRouteDescriptor] {
          \(raw: array)
        }
        """
      ]
    } catch let error as Failure {
      context.diagnose(error.diagnostic)
      return []
    }
  }

  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    // The member role diagnoses invalid input. Neither role consumes peer expansions.
    guard (try? validateController(node, declaration)) != nil else { return [] }
    var operationIDs: Set<String> = []
    var routes: Set<String> = []
    for member in declaration.memberBlock.members {
      guard let function = member.decl.as(FunctionDeclSyntax.self),
        attributes(function.attributes).contains(where: { markerNames.contains(name($0)) })
      else { continue }
      guard let route = try? documentedRoute(function),
        operationIDs.insert(route.operationID).inserted,
        routes.insert(route.identity).inserted
      else { return [] }
    }
    let result: DeclSyntax =
      """
      extension \(type.trimmed): OpenAPISchemaVapor5.OpenAPIControllerMetadata {
      }
      """
    return [result.cast(ExtensionDeclSyntax.self)]
  }
}

public struct OpenAPIMarkerMacro: PeerMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard declaration.is(FunctionDeclSyntax.self) else {
      context.diagnose(
        Failure(node, "@\(name(node)) can only be attached to a route function.").diagnostic
      )
      return []
    }
    // Only the immediate enclosing declaration counts: an outer controller must not
    // accidentally authorize annotations on local functions or nested helper types.
    guard let enclosing = context.lexicalContext.first,
      let group = enclosing.asProtocol(DeclGroupSyntax.self),
      attributes(group.attributes).contains(where: { name($0) == "OpenAPIController" })
    else {
      context.diagnose(
        Failure(
          node, "@\(name(node)) requires a direct member of an @OpenAPIController type."
        ).diagnostic
      )
      return []
    }
    return []
  }
}

private let markerNames: Set<String> = [
  "OpenAPIOperation", "OpenAPIRequestBody", "OpenAPIQuery", "OpenAPIHeader",
  "OpenAPIError", "OpenAPISecurity",
]
private let supportedMethods: Set<String> = ["GET", "POST", "PUT", "PATCH", "DELETE"]
private let routeNames = supportedMethods.union(["HTTP", "HEAD", "OPTIONS", "TRACE", "CONNECT"])
private let pathTypes: Set<String> = [
  "String", "Bool", "UUID", "Int", "Double",
]

private struct Failure: Error, DiagnosticMessage {
  let node: Syntax
  let message: String
  var severity: DiagnosticSeverity { .error }
  var diagnosticID: MessageID { MessageID(domain: "OpenAPIVaporMacros", id: "invalidMetadata") }
  var diagnostic: Diagnostic { Diagnostic(node: node, message: self) }

  init(_ node: some SyntaxProtocol, _ message: String) {
    self.node = Syntax(node)
    self.message = message
  }
}

private func attributes(_ list: AttributeListSyntax) -> [AttributeSyntax] {
  list.compactMap {
    guard case let .attribute(attribute) = $0 else { return nil }
    return attribute
  }
}

private func name(_ attribute: AttributeSyntax) -> String {
  if let identifier = attribute.attributeName.as(IdentifierTypeSyntax.self) {
    return identifier.name.text
  }
  if let member = attribute.attributeName.as(MemberTypeSyntax.self) {
    return member.name.text
  }
  return attribute.attributeName.trimmedDescription
}

private func validateController(
  _ node: AttributeSyntax, _ declaration: some DeclGroupSyntax
) throws {
  guard declaration.is(StructDeclSyntax.self) || declaration.is(ClassDeclSyntax.self)
    || declaration.is(EnumDeclSyntax.self)
  else {
    throw Failure(node, "@OpenAPIController requires a struct, class, or enum declaration.")
  }
  _ = try arguments(node, positional: 0, labels: [])
  let controllerAttributes = attributes(declaration.attributes)
  guard controllerAttributes.contains(where: {
    $0.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "Controller"
  }) else {
    throw Failure(node, "@OpenAPIController must accompany native Vapor @Controller.")
  }
  guard controllerAttributes.filter({ name($0) == "OpenAPIController" }).count == 1 else {
    throw Failure(node, "Use @OpenAPIController only once per type.")
  }
  for member in declaration.memberBlock.members {
    if let function = member.decl.as(FunctionDeclSyntax.self) {
      for attribute in function.attributes {
        guard let conditional = attribute.as(IfConfigDeclSyntax.self) else { continue }
        let finder = MarkerFinder(viewMode: .sourceAccurate)
        finder.walk(conditional)
        if let marker = finder.first {
          throw Failure(
            marker,
            "Conditional OpenAPI annotations are unsupported; annotate the route directly."
          )
        }
      }
    }
    if let conditional = member.decl.as(IfConfigDeclSyntax.self) {
      let finder = MarkerFinder(viewMode: .sourceAccurate)
      finder.walk(conditional)
      if let marker = finder.first {
        throw Failure(
          marker,
          "Documented routes inside conditional compilation are unsupported by native @Controller."
        )
      }
    }
    let conflicts: Bool
    if let variable = member.decl.as(VariableDeclSyntax.self) {
      conflicts = variable.bindings.contains {
        $0.pattern.tokens(viewMode: .sourceAccurate).contains { $0.text == "openAPIRoutes" }
      }
    } else if let named = member.decl.asProtocol(NamedDeclSyntax.self) {
      conflicts = named.name.text == "openAPIRoutes"
    } else if let cases = member.decl.as(EnumCaseDeclSyntax.self) {
      conflicts = cases.elements.contains { $0.name.text == "openAPIRoutes" }
    } else {
      conflicts = false
    }
    if conflicts {
      throw Failure(
        member.decl, "'openAPIRoutes' is reserved for @OpenAPIController metadata."
      )
    }
  }
}

private final class MarkerFinder: SyntaxVisitor {
  var first: AttributeSyntax?

  override func visit(_ node: MemberBlockSyntax) -> SyntaxVisitorContinueKind {
    .skipChildren
  }

  override func visit(_ node: CodeBlockSyntax) -> SyntaxVisitorContinueKind {
    .skipChildren
  }

  override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
    if first == nil, markerNames.contains(name(node)) {
      first = node
    }
    return .skipChildren
  }
}

private struct Arguments {
  let positional: [ExprSyntax]
  let labeled: [String: ExprSyntax]
}

private func arguments(
  _ attribute: AttributeSyntax, positional count: Int, labels: Set<String>
) throws -> Arguments {
  let list: LabeledExprListSyntax
  if attribute.arguments == nil {
    list = []
  } else if case let .argumentList(arguments) = attribute.arguments {
    list = arguments
  } else {
    throw Failure(attribute, "@\(name(attribute)) requires ordinary argument syntax.")
  }
  var positional: [ExprSyntax] = []
  var labeled: [String: ExprSyntax] = [:]
  for argument in list {
    if let label = argument.label?.text {
      guard labels.contains(label), labeled[label] == nil else {
        throw Failure(
          argument, "Unknown or duplicate @\(name(attribute)) argument label '\(label)'."
        )
      }
      labeled[label] = argument.expression
    } else {
      guard labeled.isEmpty else {
        throw Failure(argument, "Positional arguments must precede labeled arguments.")
      }
      positional.append(argument.expression)
    }
  }
  guard positional.count == count else {
    throw Failure(attribute, "@\(name(attribute)) requires \(count) positional argument(s).")
  }
  return Arguments(positional: positional, labeled: labeled)
}

private func string(_ expression: ExprSyntax, role: String) throws -> String {
  guard let literal = expression.as(StringLiteralExprSyntax.self),
    literal.openingQuote.tokenKind == .stringQuote,
    literal.openingPounds == nil,
    literal.segments.count == 1,
    let segment = literal.segments.first?.as(StringSegmentSyntax.self),
    !segment.content.text.isEmpty,
    !segment.content.text.contains("\\"),
    !segment.content.text.contains("\n"),
    !segment.content.text.contains("\r")
  else {
    throw Failure(
      expression, "\(role) must be a nonempty plain string literal without interpolation or escapes."
    )
  }
  return segment.content.text
}

private func boolean(_ expression: ExprSyntax?, default value: Bool) throws -> Bool {
  guard let expression else { return value }
  guard let literal = expression.as(BooleanLiteralExprSyntax.self) else {
    throw Failure(expression, "Expected a literal true or false.")
  }
  return literal.literal.tokenKind == .keyword(.true)
}

private func status(_ expression: ExprSyntax, error: Bool) throws -> Int {
  guard let literal = expression.as(IntegerLiteralExprSyntax.self),
    literal.literal.text.allSatisfy({ $0.isASCII && $0.isNumber }),
    let value = Int(literal.literal.text),
    (error ? 400...599 : 200...299).contains(value)
  else {
    throw Failure(
      expression,
      error
        ? "Error status must be a decimal integer literal from 400 through 599."
        : "Success status must be a decimal integer literal from 200 through 299."
    )
  }
  guard error || (value != 204 && value != 205) else {
    throw Failure(expression, "JSONResponse cannot document the bodyless HTTP status \(value).")
  }
  return value
}

private func isConcreteType(_ type: TypeSyntax) -> Bool {
  if let identifier = type.as(IdentifierTypeSyntax.self) {
    guard !["Self", "Any", "AnyObject", "Never", "Void"].contains(identifier.name.text) else {
      return false
    }
    return identifier.genericArgumentClause?.arguments.allSatisfy {
      $0.argument.as(TypeSyntax.self).map(isConcreteType) ?? false
    } ?? true
  }
  if let member = type.as(MemberTypeSyntax.self) {
    return isConcreteType(member.baseType)
      && (member.genericArgumentClause?.arguments.allSatisfy {
        $0.argument.as(TypeSyntax.self).map(isConcreteType) ?? false
      } ?? true)
  }
  if let array = type.as(ArrayTypeSyntax.self) {
    return isConcreteType(array.element)
  }
  if let dictionary = type.as(DictionaryTypeSyntax.self) {
    return isConcreteType(dictionary.key) && isConcreteType(dictionary.value)
  }
  if let optional = type.as(OptionalTypeSyntax.self) {
    return isConcreteType(optional.wrappedType)
  }
  return false
}

private func metatype(_ expression: ExprSyntax) throws -> String {
  guard let member = expression.as(MemberAccessExprSyntax.self),
    member.declName.baseName.tokenKind == .keyword(.self),
    let base = member.base
  else {
    throw Failure(expression, "Expected an explicit concrete type reference such as Model.self.")
  }
  let type = TypeSyntax(stringLiteral: base.trimmedDescription)
  guard !type.hasError, isConcreteType(type) else {
    throw Failure(expression, "Expected an explicit concrete type reference such as Model.self.")
  }
  return type.trimmedDescription
}

private func quote(_ text: String) -> String {
  StringLiteralExprSyntax(content: text).description
}

private struct DocumentedRoute {
  var method: String
  var path: [String]
  var operationID: String
  var parameters: [String]
  var requestBody: String?
  var responses: [String]
  var security: String

  var identity: String {
    method + "/" + path.map { $0.hasPrefix(":") ? ":" : $0 }.joined(separator: "/")
  }

  var expression: String {
    """
    OpenAPISchemaVapor5.OpenAPIRouteDescriptor(
      method: \(quote(method)),
      path: [\(path.map(quote).joined(separator: ", "))],
      operationID: \(quote(operationID)),
      parameters: [\(parameters.joined(separator: ", "))],
      requestBody: \(requestBody ?? "nil"),
      responses: [\(responses.joined(separator: ", "))],
      security: \(security)
    )
    """
  }
}

private func documentedRoute(_ function: FunctionDeclSyntax) throws -> DocumentedRoute {
  guard function.genericParameterClause == nil else {
    throw Failure(function.name, "Documented route handlers cannot be generic functions.")
  }
  let all = attributes(function.attributes)
  let operations = all.filter { name($0) == "OpenAPIOperation" }
  guard operations.count == 1 else {
    throw Failure(
      function.name, "A documented route requires exactly one @OpenAPIOperation."
    )
  }
  let methods = all.filter { routeNames.contains(name($0)) }
  guard methods.count == 1 else {
    throw Failure(
      function.name, "A documented route requires exactly one native @GET, @POST, @PUT, @PATCH, or @DELETE."
    )
  }
  let method = methods[0]
  guard supportedMethods.contains(name(method)),
    method.attributeName.is(IdentifierTypeSyntax.self)
  else {
    throw Failure(
      method, "Documented routes support only unqualified native @GET, @POST, @PUT, @PATCH, and @DELETE; @\(method.attributeName.trimmedDescription) is unsupported."
    )
  }
  let operation = try arguments(operations[0], positional: 1, labels: ["status"])
  let operationID = try string(operation.positional[0], role: "Operation ID")
  let successStatus = try operation.labeled["status"].map { try status($0, error: false) } ?? 200

  guard let returnType = function.signature.returnClause?.type,
    let model = jsonResponseModel(returnType)
  else {
    throw Failure(
      function.signature.returnClause.map(Syntax.init) ?? Syntax(function.name),
      "A documented route must return JSONResponse<ConcreteType>; raw, opaque, streaming, and other response types are not inferred."
    )
  }

  var route = DocumentedRoute(
    method: name(method), path: [], operationID: operationID,
    parameters: [], responses: [".json(\(successStatus), \(model).self)"],
    security: ".publicAccess"
  )
  let components: LabeledExprListSyntax
  if method.arguments == nil {
    components = []
  } else if case let .argumentList(arguments) = method.arguments {
    components = arguments
  } else {
    throw Failure(method, "Expected attached native route path arguments.")
  }
  var dynamicIndex = 0
  for component in components {
    guard component.label == nil else {
      throw Failure(
        component, "Documented controller routes do not support labeled or on: route arguments."
      )
    }
    if component.expression.is(StringLiteralExprSyntax.self) {
      let segment = try string(component.expression, role: "Route segment")
      guard !segment.contains("/"), !segment.hasPrefix(":"), !segment.contains("*") else {
        throw Failure(
          component.expression,
          "Use one literal segment per argument; manual captures, aliases, and wildcards are unsupported. Use Int.self, String.self, or another supported primitive for captures."
        )
      }
      route.path.append(segment)
    } else {
      let type = try metatype(component.expression)
      guard pathTypes.contains(type) else {
        throw Failure(
          component.expression,
          "Path types must be unqualified supported primitives (for example Int.self, String.self, UUID.self); optional, qualified, and custom path types are unsupported."
        )
      }
      guard component.expression.trimmedDescription == "\(type).self" else {
        throw Failure(
          component.expression,
          "Use canonical \(type).self spelling without internal whitespace or comments to match native capture names."
        )
      }
      let capture = type.lowercased() + String(dynamicIndex)
      dynamicIndex += 1
      route.path.append(":" + capture)
      route.parameters.append(".path(\(quote(capture)), \(type).self)")
    }
  }

  var singular: Set<String> = []
  var parameterIdentities: Set<String> = []
  var responseStatuses: Set<Int> = [successStatus]
  var securityOptional: Bool?
  for attribute in all where markerNames.contains(name(attribute)) {
    let marker = name(attribute)
    switch marker {
    case "OpenAPIOperation":
      continue
    case "OpenAPIRequestBody":
      guard singular.insert(marker).inserted else {
        throw Failure(attribute, "Use @OpenAPIRequestBody only once per route.")
      }
      let args = try arguments(attribute, positional: 1, labels: [])
      route.requestBody = ".json(\(try metatype(args.positional[0])).self)"
    case "OpenAPIQuery", "OpenAPIHeader":
      let args = try arguments(attribute, positional: 2, labels: ["required"])
      let parameterName = try string(args.positional[0], role: "Parameter name")
      let type = try metatype(args.positional[1])
      let header = marker == "OpenAPIHeader"
      let required = try boolean(args.labeled["required"], default: false)
      let location = header ? "header" : "query"
      let identity = location + ":" + (header ? parameterName.lowercased() : parameterName)
      guard parameterIdentities.insert(identity).inserted else {
        throw Failure(attribute, "Duplicate \(location) parameter '\(parameterName)'.")
      }
      route.parameters.append(
        ".\(location)(\(quote(parameterName)), \(type).self, required: \(required))"
      )
    case "OpenAPIError":
      let args = try arguments(attribute, positional: 2, labels: [])
      let code = try status(args.positional[0], error: true)
      guard responseStatuses.insert(code).inserted else {
        throw Failure(attribute, "Duplicate response status \(code).")
      }
      route.responses.append(".json(\(code), \(try metatype(args.positional[1])).self)")
    case "OpenAPISecurity":
      guard singular.insert(marker).inserted else {
        throw Failure(attribute, "Use @OpenAPISecurity only once per route.")
      }
      let args = try arguments(attribute, positional: 1, labels: ["optional"])
      let scheme = try string(args.positional[0], role: "Security scheme")
      let optional = try boolean(args.labeled["optional"], default: false)
      securityOptional = optional
      route.security = ".\(optional ? "optional" : "required")(\(quote(scheme)))"
    default:
      break
    }
  }
  let auth = all.filter { name($0) == "AuthMiddleware" }
  if let authentication = auth.first {
    guard authentication.attributeName.is(IdentifierTypeSyntax.self) else {
      throw Failure(authentication, "Use unqualified native @AuthMiddleware on documented routes.")
    }
    guard let securityOptional else {
      throw Failure(
        authentication,
        "A documented @AuthMiddleware route requires explicit @OpenAPISecurity; schemes are never inferred from authentication types."
      )
    }
    guard auth.count == 1, let args = authentication.arguments?.as(LabeledExprListSyntax.self),
      let first = args.first, first.label == nil
    else {
      throw Failure(authentication, "Expected one native @AuthMiddleware with an authentication type.")
    }
    let authType = try metatype(first.expression)
    guard first.expression.trimmedDescription == "\(authType).self" else {
      throw Failure(
        first.expression, "Use canonical \(authType).self spelling for native authentication."
      )
    }
    let optionalities = function.signature.parameterClause.parameters.dropFirst().compactMap {
      parameter -> Bool? in
      let (base, optional) = unwrapOptional(parameter.type)
      return base.trimmedDescription == authType ? optional : nil
    }
    guard !optionalities.isEmpty else {
      throw Failure(authentication, "No handler parameter matches authentication type '\(authType)'.")
    }
    guard optionalities.allSatisfy({ $0 == securityOptional }) else {
      throw Failure(
        authentication,
        "@OpenAPISecurity optional: must match the native authentication parameter's optionality."
      )
    }
  }
  return route
}

private func jsonResponseModel(_ type: TypeSyntax) -> String? {
  let arguments: GenericArgumentListSyntax?
  if let identifier = type.as(IdentifierTypeSyntax.self), identifier.name.text == "JSONResponse" {
    arguments = identifier.genericArgumentClause?.arguments
  } else if let member = type.as(MemberTypeSyntax.self), member.name.text == "JSONResponse",
    member.baseType.trimmedDescription == "OpenAPISchemaVapor5"
  {
    arguments = member.genericArgumentClause?.arguments
  } else {
    return nil
  }
  guard let arguments, arguments.count == 1,
    let model = arguments.first?.argument.as(TypeSyntax.self),
    isConcreteType(model)
  else { return nil }
  return model.trimmedDescription
}

private func unwrapOptional(_ type: TypeSyntax) -> (TypeSyntax, Bool) {
  if let optional = type.as(OptionalTypeSyntax.self) {
    return (optional.wrappedType, true)
  }
  if let identifier = type.as(IdentifierTypeSyntax.self), identifier.name.text == "Optional",
    let arguments = identifier.genericArgumentClause?.arguments, arguments.count == 1,
    let argument = arguments.first?.argument.as(TypeSyntax.self)
  {
    return (argument, true)
  }
  return (type, false)
}
