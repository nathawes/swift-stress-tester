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

import Foundation
import SwiftSourceKit
import SwiftSyntax
import Common
import Basic

struct StressTester {
  let file: URL
  let source: String
  let compilerArgs: [String]
  let options: StressTesterOptions
  let connection: SwiftSourceKitFramework

  init(for file: URL, compilerArgs: [String], options: StressTesterOptions) {
    self.file = file
    self.source = try! String(contentsOf: file, encoding: .utf8)
    self.compilerArgs = compilerArgs
    self.options = options
    self.connection = try! SwiftSourceKitFramework()
  }

  var generator: ActionGenerator {
    switch options.rewriteMode {
    case .none:
      return RequestActionGenerator()
    case .basic:
      return RewriteActionGenerator()
    case .insideOut:
      return InsideOutRewriteActionGenerator()
    case .concurrent:
      return ConcurrentRewriteActionGenerator()
    }
  }

  func computeStartStateAndActions(from tree: SourceFileSyntax) -> (state: SourceState, actions: [Action]) {
    let limit = options.astBuildLimit ?? Int.max
    var astRebuilds = 0
    var locationsInvalidated = false

    let pages = generator
      .generate(for: tree)
      .filter { action in
        guard !locationsInvalidated else { return false }
        switch action {
        case .cursorInfo:
          return options.requests.contains(.cursorInfo)
        case .rangeInfo:
          return options.requests.contains(.rangeInfo)
        case .codeComplete:
          guard options.requests.contains(.codeComplete), astRebuilds <= limit else { return false }
          astRebuilds += 1
          return true
        case .replaceText:
          guard astRebuilds <= limit else {
            locationsInvalidated = true
            return false
          }
          astRebuilds += 1
          return true
        }
      }
      .divide(into: options.page.count)

    let page = Array(pages[options.page.index])
    guard !options.page.isFirst else {
      return (SourceState(rewriteMode: options.rewriteMode, content: source), page)
    }

    // Compute the initial state of the source file for this page
    var state = SourceState(rewriteMode: options.rewriteMode, content: source)
    pages[0..<options.page.index].joined().forEach {
      if case .replaceText(let range, let text) = $0 {
        state.replace(range, with: text)
      }
    }
    return (state, page)
  }

  func run() throws {
    if options.rewriteMode == .none {
      try readOnlyRun()
    } else {
      try rewriteRun()
    }
  }

  private func readOnlyRun() throws {
    var document = SourceKitDocument(file.path, args: compilerArgs, connection: connection, listener: options.listener)

    let (tree, _) = try document.open()
    let (state, actions) = self.computeStartStateAndActions(from: tree!)

    // The action reording below requires no actions that modify the source
    // buffer are present
    precondition(!state.wasModified && actions.allSatisfy {
      switch $0 {
      case .replaceText:
        return false
      default:
        return true
      }
    })

    // Run all requests that can reuse a single AST together for improved
    // runtime
    let cursorInfos = actions.compactMap { action -> SourcePosition? in
      guard case .cursorInfo(let position) = action else { return nil }
      return position
    }
    let rangeInfos = actions.compactMap { action -> SourceRange? in
      guard case .rangeInfo(let range) = action else { return nil }
      return range
    }
    let codeCompletions = actions.compactMap { action -> SourcePosition? in
      guard case .codeComplete(let position) = action else { return nil }
      return position
    }

    for position in cursorInfos {
      _ = try document.cursorInfo(position: position)
    }

    for range in rangeInfos {
      _ = try document.rangeInfo(start: range.start, length: range.length)
    }

    for position in codeCompletions {
      _ = try document.codeComplete(offset: position.offset)
    }

    _ = try document.close()
  }

  private func rewriteRun() throws {
    var document = SourceKitDocument(file.path, args: compilerArgs, connection: connection, containsErrors: true, listener: options.listener)

    // compute the actions for the entire tree
    let (tree, _) = try document.open()
    let (state, actions) = computeStartStateAndActions(from: tree!)

    // reopen the document in the starting state
    _ = try document.close()
    _ = try document.open(state: state)

    for action in actions {
      switch action {
      case .cursorInfo(let position):
        _ = try document.cursorInfo(position: position)
      case .codeComplete(let position):
        _ = try document.codeComplete(offset: position.offset)
      case .rangeInfo(let range):
        _ = try document.rangeInfo(start: range.start, length: range.length)
      case .replaceText(let range, let text):
        _ = try document.replaceText(range: range, text: text)
      }
    }

    _ = try document.close()
  }
}

struct StressTesterOptions {
  var astBuildLimit: Int? = nil
  var requests: RequestSet = .all
  var rewriteMode: RewriteMode = .none
  var page = Page(1, of: 1)
  var listener: RequestListener? = nil
}

public struct RequestSet: OptionSet {
  public let rawValue: Int

  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  public var valueNames: [String] {
    var requests = [String]()
    if self.contains(.codeComplete) {
      requests.append("CodeComplete")
    }
    if self.contains(.cursorInfo) {
      requests.append("CursorInfo")
    }
    if self.contains(.rangeInfo) {
      requests.append("RangeInfo")
    }
    return requests
  }

  public static let cursorInfo = RequestSet(rawValue: 1 << 0)
  public static let rangeInfo = RequestSet(rawValue: 1 << 1)
  public static let codeComplete = RequestSet(rawValue: 1 << 2)

  public static let all: RequestSet = [.cursorInfo, .rangeInfo, .codeComplete]
}
