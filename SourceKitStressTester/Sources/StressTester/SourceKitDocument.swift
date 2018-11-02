//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SwiftSourceKit
import CSourcekitd
import SwiftSyntax
import Common
import Foundation

enum SyntacticInfoMode {
  case syntaxTreeJson
  case syntaxTreeByte
  case syntaxMap

  func updateRequest(_ request: SKRequestDictionary, connection: SwiftSourceKitFramework, incremental: Bool) {
    switch self {
    case .syntaxTreeJson:
      request[connection.keys.enablesyntaxmap] = 0
      request[connection.keys.enablesubstructure] = 0
      request[connection.keys.syntaxtreetransfermode] = incremental
        ? connection.values.syntaxtree_transfer_incremental
        : connection.values.syntaxtree_transfer_full
      request[connection.keys.syntax_tree_serialization_format] = connection.values.syntaxtree_serialization_format_json
    case .syntaxTreeByte:
      request[connection.keys.enablesyntaxmap] = 0
      request[connection.keys.enablesubstructure] = 0
      request[connection.keys.syntaxtreetransfermode] = incremental
        ? connection.values.syntaxtree_transfer_incremental
        : connection.values.syntaxtree_transfer_full
      request[connection.keys.syntax_tree_serialization_format] = connection.values.syntaxtree_serialization_format_bytetree
    case .syntaxMap:
      request[connection.keys.syntaxtreetransfermode] = connection.values.syntaxtree_transfer_off
      request[connection.keys.enablesyntaxmap] = 1
      request[connection.keys.enablesubstructure] = 1
    }
    request[connection.keys.syntactic_only] = 1
  }
}

struct SourceKitDocument {
  let file: String
  let args: [String]
  let containsErrors: Bool
  let connection: SwiftSourceKitFramework
  let listener: RequestListener?

  private var deserializer: SyntaxTreeDeserializer? = nil
  private var tree: SourceFileSyntax? = nil
  private var sourceState: SourceState? = nil

  private var documentInfo: DocumentInfo {
    var modification: DocumentModification? = nil
    if let state = sourceState, state.wasModified {
      modification = DocumentModification(mode: state.mode, content: state.source)
    }
    return DocumentInfo(path: file, modification: modification)
  }

  init(_ file: String, args: [String], connection: SwiftSourceKitFramework, containsErrors: Bool = false, listener: RequestListener? = nil) {
    self.file = file
    self.args = args
    self.containsErrors = containsErrors
    self.connection = connection
    self.listener = listener
  }

  mutating func open(state: SourceState? = nil, mode: SyntacticInfoMode = .syntaxMap) throws -> (SourceFileSyntax?, SKResponseDictionary) {
    let request = SKRequestDictionary(sourcekitd: connection)
    request[connection.keys.request] = connection.requests.editor_open

    if let state = state {
      sourceState = state
      request[connection.keys.sourcetext] = state.source
    } else {
      request[connection.keys.sourcefile] = file
    }
    request[connection.keys.name] = file
    mode.updateRequest(request, connection: connection, incremental: false)

    let compilerArgs = SKRequestArray(sourcekitd: connection)
    for arg in args { compilerArgs.append(arg) }
    request[connection.keys.compilerargs] = compilerArgs

    let info = RequestInfo.editorOpen(document: documentInfo)
    let result = try sendWithTimeout(request, info: info)
    let response = try throwIfInvalid(result, request: info)

    deserializer = SyntaxTreeDeserializer()
    try updateSyntaxTree(response, request: info, mode: mode)

    return (tree, response)
  }

  mutating func close() throws -> SKResponseDictionary {
    sourceState = nil

    let request = SKRequestDictionary(sourcekitd: connection)
    request[connection.keys.request] = connection.requests.editor_close

    request[connection.keys.sourcefile] = file
    request[connection.keys.name] = file

    let info = RequestInfo.editorClose(document: documentInfo)
    let response = try sendWithTimeout(request, info: info)
    return try throwIfInvalid(response, request: info)
  }

  func rangeInfo(start: SourcePosition, length: Int) throws -> SKResponseDictionary {
    let request = SKRequestDictionary(sourcekitd: connection)
    request[connection.keys.request] = connection.requests.rangeinfo

    request[connection.keys.sourcefile] = file
    request[connection.keys.offset] = start.offset
    request[connection.keys.length] = length
    request[connection.keys.retrieve_refactor_actions] = 1

    let compilerArgs = SKRequestArray(sourcekitd: connection)
    for arg in args { compilerArgs.append(arg) }
    request[connection.keys.compilerargs] = compilerArgs

    let info = RequestInfo.rangeInfo(document: documentInfo, offset: start.offset, length: length, args: args)
    let result = try sendWithTimeout(request, info: info)
    let response = try throwIfInvalid(result, request: info)

    if let actions: SKResponseArray = response[connection.keys.refactor_actions] {
      try actions.forEach { int, action in
        let actionName: String = action[connection.keys.actionname]!
        let kind: sourcekitd_uid_t = action[connection.keys.actionuid]!
        _ = try semanticRefactoring(actionKind: kind, actionName: actionName,
                                    position: start)
        return true
      }
    }

    return response
  }

  func cursorInfo(position: SourcePosition) throws -> SKResponseDictionary {
    let request = SKRequestDictionary(sourcekitd: connection)
    request[connection.keys.request] = connection.requests.cursorinfo

    request[connection.keys.sourcefile] = file
    request[connection.keys.offset] = position.offset
    request[connection.keys.retrieve_refactor_actions] = 1

    let compilerArgs = SKRequestArray(sourcekitd: connection)
    for arg in args { compilerArgs.append(arg) }
    request[connection.keys.compilerargs] = compilerArgs

    let info = RequestInfo.cursorInfo(document: documentInfo, offset: position.offset, args: args)
    let result = try sendWithTimeout(request, info: info)
    let response = try throwIfInvalid(result, request: info)

    if !containsErrors {
      if let typeName: String = response[connection.keys.typename], typeName.contains("<<error type>>") {
        throw SourceKitError.failed(.errorTypeInResponse, request: info, response: response.description)
      }
    }

    let symbolName: String? = response[connection.keys.name]
    if let actions: SKResponseArray = response[connection.keys.refactor_actions] {
      try actions.forEach { int, action in
        let actionName: String = action[connection.keys.actionname]!
        guard actionName != "Global Rename" else { return true }
        let kind: sourcekitd_uid_t = action[connection.keys.actionuid]!
        _ = try semanticRefactoring(actionKind: kind, actionName: actionName,
                                    position: position, newName: symbolName)
        return true
      }
    }

    return response
  }

  func semanticRefactoring(actionKind: sourcekitd_uid_t, actionName: String,
                           position: SourcePosition, newName: String? = nil) throws -> SKResponseDictionary {
    let request = SKRequestDictionary(sourcekitd: connection)
    request[connection.keys.request] = connection.requests.refactoring

    request[connection.keys.actionuid] = actionKind
    request[connection.keys.sourcefile] = file
    request[connection.keys.line] = position.line
    request[connection.keys.column] = position.column

    if let newName = newName, actionName == "Local Rename" {
      request[connection.keys.name] = newName
    }

    let compilerArgs = SKRequestArray(sourcekitd: connection)
    for arg in args { compilerArgs.append(arg) }
    request[connection.keys.compilerargs] = compilerArgs

    let info = RequestInfo.semanticRefactoring(document: documentInfo, offset: position.offset, kind: actionName, args: args)
    let result = try sendWithTimeout(request, info: info)
    let response = try throwIfInvalid(result, request: info)

    return response
  }

  func codeComplete(offset: Int) throws -> SKResponseDictionary {
    let request = SKRequestDictionary(sourcekitd: connection)
    request[connection.keys.request] = connection.requests.codecomplete

    request[connection.keys.sourcefile] = file
    request[connection.keys.offset] = offset

    let compilerArgs = SKRequestArray(sourcekitd: connection)
    for arg in args { compilerArgs.append(arg) }
    request[connection.keys.compilerargs] = compilerArgs

    let info = RequestInfo.codeComplete(document: documentInfo, offset: offset, args: args)
    let result = try sendWithTimeout(request, info: info)
    let response = try throwIfInvalid(result, request: info)

    return response
  }

  mutating func replaceText(range: SourceRange, text: String, mode: SyntacticInfoMode = .syntaxMap) throws -> (SourceFileSyntax?, SKResponseDictionary) {
    let request = SKRequestDictionary(sourcekitd: connection)
    request[connection.keys.request] = connection.requests.editor_replacetext

    request[connection.keys.name] = file
    request[connection.keys.offset] = range.start.offset
    request[connection.keys.length] = range.length
    request[connection.keys.sourcetext] = text

    mode.updateRequest(request, connection: connection, incremental: true)

    let compilerArgs = SKRequestArray(sourcekitd: connection)
    for arg in args { compilerArgs.append(arg) }
    request[connection.keys.compilerargs] = compilerArgs

    let info = RequestInfo.editorReplaceText(document: documentInfo, offset: range.start.offset, length: range.length, text: text)
    let result = try sendWithTimeout(request, info: info)
    let response = try throwIfInvalid(result, request: info)

    // update expected source content and syntax tree
    sourceState?.replace(range, with: text)
    try updateSyntaxTree(response, request: info, mode: mode)

    return (tree, response)
  }

  private func sendWithTimeout(_ request: SKRequestDictionary, info: RequestInfo) throws -> SKResult<SKResponseDictionary> {
    var response: SKResult<SKResponseDictionary>? = nil
//    let completed = DispatchSemaphore(value: 0)
    let timeBeforeSend = Date()
    response = connection.sendSync(request)
//    let handle = connection.send(request) {
//      response = $0
//      completed.signal()
//    }
//    switch completed.wait(timeout: .now() + DispatchTimeInterval.seconds(60)) {
//    case .success:
//      _ = handle
      listener?.receivedResponse(for: info, after: -timeBeforeSend.timeIntervalSinceNow)
//      print(response?.description ?? "")
      return response!
//    case .timedOut:
//      throw SourceKitError.timedOut(request: info)
//    }

  }

  private func throwIfInvalid(_ result: SKResult<SKResponseDictionary>, request: RequestInfo) throws -> SKResponseDictionary {
//    if response.isCompilerCrash || response.isConnectionInterruptionError {
//      throw SourceKitError.crashed(request: request)
//    }
//    // FIXME: We don't supply a valid new name for initializer calls for local
//    // rename requests. Ignore these errors for now.
//    if response.isError, !response.description.contains("does not match the arity of the old name") {
//      throw SourceKitError.failed(.errorResponse, request: request, response: response.description.chomp())
//    }

    switch result {
    case .success(let dict):
      return dict
    case .failure(_):
      // FIXME: Actually do this check properly
      fatalError("didn't handle reponse!!!!!")
    }
  }

  @discardableResult
  private mutating func updateSyntaxTree(_ response: SKResponseDictionary, request: RequestInfo, mode: SyntacticInfoMode) throws -> SourceFileSyntax? {
    precondition(deserializer != nil)

    let timeBeforeDeserialization = Date()
    do {
      switch mode {
      case .syntaxTreeJson:
        guard let treeJson: String = response[connection.keys.serialized_syntax_tree] else { return nil }
        let tree = try deserializer!.deserialize(treeJson.data(using: .utf8)!, serializationFormat: .json)
        listener?.deserializedTree(for: request, after: -timeBeforeDeserialization.timeIntervalSinceNow)
        self.tree = tree
      case .syntaxTreeByte:
        guard let treeData: Data = response[connection.keys.serialized_syntax_tree] else { return nil }
        let tree = try deserializer!.deserialize(treeData, serializationFormat: .byteTree)
        listener?.deserializedTree(for: request, after: -timeBeforeDeserialization.timeIntervalSinceNow)
        self.tree = tree
      case .syntaxMap:
        return nil
      }
    } catch {
      throw SourceKitError.failed(.errorDeserializingSyntaxTree, request: request, response: response.description)
    }

    if let state = sourceState, state.source != tree!.description {
      // FIXME: add state and tree descriptions in their own field
      let comparison = """
        \(response.description)
        --source-state------
        \(state.source)
        --tree-description--
        \(tree!.description)
        --end---------------
        """
      throw SourceKitError.failed(.sourceAndSyntaxTreeMismatch, request: request, response: comparison)
    }

    return tree
  }
}

/// Tracks the current state of a source file
struct SourceState {
  let mode: RewriteMode
  var source: String
  var wasModified: Bool

  init(rewriteMode: RewriteMode, content source: String, wasModified: Bool = false) {
    self.mode = rewriteMode
    self.source = source
    self.wasModified = wasModified
  }

  /// - returns: true if source state changed
  @discardableResult
  mutating func replace(_ range: SourceRange, with text: String) -> Bool {
    let bytes = source.utf8
    let prefix = bytes.prefix(upTo: bytes.index(bytes.startIndex, offsetBy: range.start.offset))
    let suffix = bytes.suffix(from: bytes.index(bytes.startIndex, offsetBy: range.end.offset))
    source = String(prefix)! + text + String(suffix)!
    let changed = !range.isEmpty || !text.isEmpty
    wasModified = wasModified || changed
    return changed
  }
}

protocol RequestListener {
  func receivedResponse(for request: RequestInfo, after seconds: TimeInterval)
  func deserializedTree(for request: RequestInfo, after seconds: TimeInterval)
}
