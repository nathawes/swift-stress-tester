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
import Common
import Utility
import Basic
import SwiftSyntax

public struct SyntacticPerfTesterTool {
  let parser: ArgumentParser
  let arguments: [String]

  let usage = "<options> <source-file>"
  let overview = "A utility for finding measuring the performance of SourceKit's syntactic requests"

  /// Arguments
  let mode: OptionArgument<RewriteMode>
  let file: PositionalArgument<PathArgument>

  public init(arguments: [String]) {
    self.arguments = Array(arguments.dropFirst())

    self.parser = ArgumentParser(usage: usage, overview: overview)
    mode = parser.add(
      option: "--rewrite-mode", shortName: "-m", kind: RewriteMode.self,
      usage: "<MODE> One of 'none' (default), 'basic', 'concurrent', or 'insideOut'")
    file = parser.add(
      positional: "<source-file>", kind: PathArgument.self, optional: false,
      usage: "A Swift source file to test", completion: .filename)
  }

  public func run() throws -> Bool {
    let results = try parse()
    return try process(results)
  }

  func parse() throws -> ArgumentParser.Result {
    return try parser.parse(arguments)
  }

  private func process(_ arguments: ArgumentParser.Result) throws -> Bool {
    var options = SyntacticPerfTesterOptions()
    if let mode = arguments.get(mode) {
      options.rewriteMode = mode
    }

    var collector = PerformanceDataCollector()

    let absoluteFile = URL(fileURLWithPath: arguments.get(file)!.path.asString)

    let tester = SyntacticPerfTester(for: absoluteFile, collector: collector, options: options)
    try tester.run()
    stdoutStream <<< collector.description
    stdoutStream.flush()
    return true
  }
}

