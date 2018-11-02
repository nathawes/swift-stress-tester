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

struct SyntacticPerfTester {
  let file: URL
  let connection: SwiftSourceKitFramework
  let options: SyntacticPerfTesterOptions
  let collector: PerformanceDataCollector

  init(for file: URL, collector: PerformanceDataCollector, options: SyntacticPerfTesterOptions) {
    self.file = file
    self.collector = collector
    self.options = options
    self.connection = try! SwiftSourceKitFramework()
  }

  var generator: ActionGenerator? {
    switch options.editMode {
    case .none:
      return nil
    case .reinsertTokenByToken:
      return ReinsertEditActionGenerator()
    case .reinsertMostDeeplyNestedToken:
      return RepeatEditActionGenerator(repeatCount: options.repeatCount)
    }
  }

  var walker: SyntaxVisitor? {
    switch options.walkMode {
    case .none:
      return nil
    case .countNodes:
      return CountingVisitor()
    case .computeNodeLocations:
      return LocationComputingVisitor()
    }
  }

  func computeActions(from tree: SourceFileSyntax) -> [Action] {
    return generator?
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
      } ?? []
  }

  func run() throws {
    var document = SourceKitDocument(file.path, args: [], connection: connection, containsErrors: true, listener: collector)

    collector.stopListening()
    let (tree, _) = try document.open(mode: .syntaxTreeByte)
    collector.resumeListening()


    // test first open performance
    for _ in 0..<options.repeatCount {
      _ = try document.close()
      _ = try document.open(mode: .syntaxTreeByte)
    }

    // test edit performance
    for action in computeActions(from: tree!) {
      switch action {
      case .cursorInfo: fallthrough
      case .codeComplete: fallthrough
      case .rangeInfo:
        fatalError("Didn't filter out semantic request")
      case .replaceText(let range, let text):
        _ = try document.replaceText(range: range, text: text, mode: .syntaxTreeByte)
      }
    }

    // test tree walk performance
    if let walker = self.walker {
      for _ in 0..<options.repeatCount {
        let timeBeforeWalk = Date()
        walker.visit(tree!)
        collector.finishedTreeWalk(after: -timeBeforeWalk.timeIntervalSinceNow)
      }
    }

    _ = try document.close()
  }
}

enum EditMode {
  case none
  case reinsertTokenByToken
  case reinsertMostDeeplyNestedToken
}

enum WalkMode {
  case none
  case countNodes
  case computeNodeLocations
}

struct SyntacticPerfTesterOptions {
  var repeatCount: Int = 100
  var editMode: EditMode = .reinsertMostDeeplyNestedToken
  var walkMode: WalkMode = .countNodes
}
