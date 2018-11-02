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
  let editMode: OptionArgument<EditMode>
  let walkMode: OptionArgument<WalkMode>
  let repeatCount: OptionArgument<Int>
  let file: PositionalArgument<PathArgument>

  public init(arguments: [String]) {
    self.arguments = Array(arguments.dropFirst())

    self.parser = ArgumentParser(usage: usage, overview: overview)
    editMode = parser.add(
      option: "--edit-mode", shortName: "-e", kind: EditMode.self,
      usage: "<MODE> One of 'none', 'reinsertAll', or 'reinsertDeepest'")
    walkMode = parser.add(
      option: "--walk-mode", shortName: "-w", kind: WalkMode.self,
      usage: "<MODE> One of 'none', 'countNodes', or 'computeNodeLocations'")
    repeatCount = parser.add(
      option: "--repeat", shortName: "-n", kind: Int.self,
      usage: "<N> The number of times to repeat operations (default: 100)")
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
    if let repeatCount = arguments.get(self.repeatCount) {
      options.repeatCount = repeatCount
    }

    if let mode = arguments.get(editMode) {
      options.editMode = mode
    }

    let collector = PerformanceDataCollector()
    let absoluteFile = URL(fileURLWithPath: arguments.get(file)!.path.asString)
    let tester = SyntacticPerfTester(for: absoluteFile, collector: collector, options: options)
    try tester.run()

    stdoutStream <<< collector.description <<< "\n"
    stdoutStream.flush()

    return true
  }
}


extension EditMode: ArgumentKind {
  init(argument: String) throws {
    switch argument {
    case "none":
      self = .none
    case "reinsertAll":
      self = .reinsertTokenByToken
    case "reinsertDeepest":
      self = .reinsertMostDeeplyNestedToken
    default:
      throw ArgumentConversionError.unknown(value: argument)
    }
  }

  static var completion: ShellCompletion = .none
}


extension WalkMode: ArgumentKind {
  init(argument: String) throws {
    switch argument {
    case "none":
      self = .none
    case "countNodes":
      self = .countNodes
    case "computeNodeLocations":
      self = .computeNodeLocations
    default:
      throw ArgumentConversionError.unknown(value: argument)
    }
  }

  static var completion: ShellCompletion = .none
}
