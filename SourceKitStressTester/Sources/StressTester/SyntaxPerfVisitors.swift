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

import SwiftSyntax

final class CountingVisitor: SyntaxVisitor {
  var count = 0

  override func visitPre(_ node: Syntax) {
    count += 1
  }
}

final class LocationComputingVisitor: SyntaxVisitor {
  var lastStart: AbsolutePosition? = nil
  var lastEnd: AbsolutePosition? = nil

  override func visitPre(_ node: Syntax) {
    lastStart = node.position
    lastEnd = node.endPositionAfterTrailingTrivia
  }
}
