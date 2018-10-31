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
import SwiftLang
import SwiftSyntax
import Common

struct SyntacticPerfTester {
  let file: URL
  let connection: SourceKitdService
  let options: SyntacticPerfTesterOptions
  let collector: PerformanceDataCollector

  init(for file: URL, collector: PerformanceDataCollector, options: SyntacticPerfTesterOptions) {
    self.file = file
    self.collector = collector
    self.options = options
    self.connection = SourceKitdService()
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

  func computeActions(from tree: SourceFileSyntax) -> [Action] {
    return generator
      .generate(for: tree)
      .filter { action in
        switch action {
        case .cursorInfo: fallthrough
        case .rangeInfo: fallthrough
        case .codeComplete:
          return false
        case .replaceText:
          return true
        }
      }
  }

  func run() throws {
    var document = SourceKitDocument(file.path, args: [], connection: connection, containsErrors: true, listener: collector)

    // compute the actions for the entire tree
    let (tree, _) = try document.open()

    for action in computeActions(from: tree) {
      switch action {
      case .cursorInfo: fallthrough
      case .codeComplete: fallthrough
      case .rangeInfo:
        fatalError("Didn't filter out semantic request")
      case .replaceText(let range, let text):
        _ = try document.replaceText(range: range, text: text)
      }
    }

    _ = try document.close()
  }
}

struct SyntacticPerfTesterOptions {
  var rewriteMode: RewriteMode = .none
}
