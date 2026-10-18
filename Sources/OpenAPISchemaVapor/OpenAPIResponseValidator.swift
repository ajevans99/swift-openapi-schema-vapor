import Foundation
import JSONSchema
import OrderedCollections
import OrderedJSON
import Vapor

/// Checks an HTTP response against the response an OpenAPI 3.1 document declares for it.
///
/// Use it in tests to keep handler behavior and the generated document in parity: the
/// status must be documented, required response headers must be present, the media type
/// must be declared, and JSON bodies must validate against the documented schema.
/// Local `#/components/...` references are resolved; external references are not.
public struct OpenAPIResponseValidator: Sendable {
  public let document: JSONValue

  public init(document: JSONValue) {
    self.document = document
  }

  public init(data: Data) throws {
    self.init(document: try JSONValue.parse(data))
  }

  /// Returns the problems found; an empty array means the response matches the document.
  public func validate(
    operationID: String,
    status: Int,
    headers: HTTPHeaders = [:],
    body: Data = Data()
  ) -> [String] {
    guard let operation = operation(withID: operationID) else {
      return ["Operation '\(operationID)' is not documented."]
    }
    return validate(operation, label: operationID, status: status, headers: headers, body: body)
  }

  /// Looks up the operation by method and documented path template, such as `/pets/{petID}`.
  public func validate(
    method: Vapor.HTTPMethod,
    path: String,
    status: Int,
    headers: HTTPHeaders = [:],
    body: Data = Data()
  ) -> [String] {
    let label = "\(method.rawValue) \(path)"
    guard
      let operation = resolved(
        document.object?["paths"]?.object?[path]?.object?[method.rawValue.lowercased()])
    else {
      return ["Operation \(label) is not documented."]
    }
    return validate(operation, label: label, status: status, headers: headers, body: body)
  }

  public func validate(
    operationID: String,
    status: Vapor.HTTPStatus,
    headers: HTTPHeaders = [:],
    body: ByteBuffer
  ) -> [String] {
    validate(
      operationID: operationID,
      status: Int(status.code),
      headers: headers,
      body: Data(body.readableBytesView)
    )
  }

  /// Throws `OpenAPIResponseValidationError` when the response does not match.
  public func assertValid(
    operationID: String,
    status: Int,
    headers: HTTPHeaders = [:],
    body: Data = Data()
  ) throws {
    let problems = validate(operationID: operationID, status: status, headers: headers, body: body)
    guard problems.isEmpty else {
      throw OpenAPIResponseValidationError(problems: problems)
    }
  }

  private func operation(withID operationID: String) -> JSONValue? {
    for (_, item) in document.object?["paths"]?.object ?? [:] {
      for (_, operation) in resolved(item)?.object ?? [:] {
        if operation.object?["operationId"]?.string == operationID {
          return operation
        }
      }
    }
    return nil
  }

  private func validate(
    _ operation: JSONValue,
    label: String,
    status: Int,
    headers: HTTPHeaders,
    body: Data
  ) -> [String] {
    let responses = operation.object?["responses"]?.object ?? [:]
    let statusKey = String(status)
    let rangeKey = "\(status / 100)XX"
    guard
      let response = resolved(
        responses[statusKey] ?? responses[rangeKey] ?? responses[rangeKey.lowercased()]
          ?? responses["default"])
    else {
      let documented = responses.keys.joined(separator: ", ")
      return ["\(label) returned status \(status), but documents only [\(documented)]."]
    }

    var problems: [String] = []
    for (name, header) in response.object?["headers"]?.object ?? [:] {
      if resolved(header)?.object?["required"]?.boolean == true, headers.first(name: name) == nil {
        problems.append("\(label) \(status) response is missing required header '\(name)'.")
      }
    }

    let content = response.object?["content"]?.object ?? [:]
    let contentType = headers.first(name: .contentType)
    if content.isEmpty {
      if !body.isEmpty {
        problems.append("\(label) \(status) response has a body, but the document declares no content.")
      }
      return problems
    }
    guard let contentType else {
      problems.append(
        "\(label) \(status) response has no Content-Type; expected one of [\(content.keys.joined(separator: ", "))].")
      return problems
    }
    let mediaType = contentType.split(separator: ";", maxSplits: 1)[0]
      .trimmingCharacters(in: .whitespaces).lowercased()
    let typeWildcard = (mediaType.split(separator: "/").first.map(String.init) ?? mediaType) + "/*"
    guard let mediaObject = content[mediaType] ?? content[typeWildcard] ?? content["*/*"] else {
      problems.append(
        "\(label) \(status) response Content-Type '\(mediaType)' is not one of [\(content.keys.joined(separator: ", "))]."
      )
      return problems
    }
    guard isJSONMediaType(mediaType), let schema = mediaObject.object?["schema"] else {
      return problems
    }
    let instance: JSONValue
    do {
      instance = try JSONValue.parse(body)
    } catch {
      problems.append("\(label) \(status) response body is not valid JSON: \(error).")
      return problems
    }
    problems += validate(instance, against: schema).map { "\(label) \(status) response body: \($0)" }
    return problems
  }

  private func validate(_ instance: JSONValue, against schema: JSONValue) -> [String] {
    var definitions: OrderedDictionary<String, JSONValue> = [:]
    for (name, component) in document.object?["components"]?.object?["schemas"]?.object ?? [:] {
      definitions[name] = rewritingComponentReferences(component)
    }
    let root: JSONValue = .object([
      "$defs": .object(definitions),
      "allOf": .array([rewritingComponentReferences(schema)]),
    ])
    do {
      let validator = try JSONSchema.Schema(
        rawSchema: root,
        context: JSONSchema.Context(dialect: .draft2020_12)
      )
      let result = validator.validate(instance)
      guard !result.isValid else { return [] }
      return result.errors?.map(flatten) ?? ["Invalid instance."]
    } catch {
      return ["Documented schema could not be loaded: \(error)."]
    }
  }

  /// Follows local Reference Objects, such as `#/components/responses/NotFound`.
  private func resolved(_ value: JSONValue?) -> JSONValue? {
    var current = value
    for _ in 0..<32 {
      guard let reference = current?.object?["$ref"]?.string else { return current }
      guard reference.hasPrefix("#/") else { return nil }
      var target: JSONValue? = document
      for token in reference.dropFirst(2).split(separator: "/", omittingEmptySubsequences: false) {
        let key = token.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
        target = target?.object?[key]
      }
      current = target
    }
    return nil
  }
}

public struct OpenAPIResponseValidationError: Error, CustomStringConvertible, Equatable {
  public let problems: [String]

  public init(problems: [String]) {
    self.problems = problems
  }

  public var description: String {
    "Response does not match the OpenAPI document: " + problems.joined(separator: "; ")
  }
}

private func isJSONMediaType(_ mediaType: String) -> Bool {
  mediaType == "application/json" || mediaType.hasSuffix("+json")
}

private let componentSchemaPrefix = "#/components/schemas/"

private func rewritingComponentReferences(_ value: JSONValue) -> JSONValue {
  switch value {
  case .object(let object):
    var rewritten: OrderedDictionary<String, JSONValue> = [:]
    for (key, member) in object {
      if key == "$ref", case .string(let reference) = member, reference.hasPrefix(componentSchemaPrefix) {
        rewritten[key] = .string("#/$defs/" + reference.dropFirst(componentSchemaPrefix.count))
      } else {
        rewritten[key] = rewritingComponentReferences(member)
      }
    }
    return .object(rewritten)
  case .array(let values):
    return .array(values.map(rewritingComponentReferences))
  default:
    return value
  }
}

private func flatten(_ error: JSONSchema.ValidationError) -> String {
  let message = "\(error.keyword) at '\(error.instanceLocation)': \(error.message)"
  guard let errors = error.errors, !errors.isEmpty else {
    return message
  }
  return ([message] + errors.map(flatten)).joined(separator: " -> ")
}
