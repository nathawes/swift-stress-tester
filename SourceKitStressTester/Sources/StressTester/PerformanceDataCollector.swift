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

import Common

final class PerformanceDataCollector: RequestListener, CustomStringConvertible {
  fileprivate enum RequestType: String {
    case editorOpen, editorClose, replaceText, cursorInfo, codeComplete, rangeInfo, semanticRefactoring
  }

  var listening = true
  private var responseTime = PerformanceGroup<RequestType>(title: "SourceKit response time")
  private var deserializationTime = PerformanceGroup<RequestType>(title: "Syntax tree deserialization time")
  private var treeWalkTime = PerformanceSeries(label: "Syntax tree walk time")

  var description: String {
    return ([responseTime, deserializationTime, treeWalkTime] as [CustomStringConvertible])
      .map {$0.description}
      .joined(separator: "\n")
  }

  func stopListening() {
    listening = false
  }

  func resumeListening() {
    listening = true
  }

  func receivedResponse(for request: RequestInfo, after seconds: Double) {
    guard listening else { return }
    responseTime.append(seconds, to: RequestType(request))
  }

  func deserializedTree(for request: RequestInfo, after seconds: Double) {
    guard listening else { return }
    deserializationTime.append(seconds, to: RequestType(request))
  }

  func finishedTreeWalk(after seconds: Double) {
    treeWalkTime.append(seconds)
  }
}

extension PerformanceDataCollector.RequestType {
  init(_ info: RequestInfo) {
    switch info {
    case .editorOpen:
      self = .editorOpen
    case .editorReplaceText:
      self = .replaceText
    case .editorClose:
      self = .editorClose
    case .cursorInfo:
      self = .cursorInfo
    case .codeComplete:
      self = .codeComplete
    case .rangeInfo:
      self = .rangeInfo
    case .semanticRefactoring:
      self = .semanticRefactoring
    }
  }
}


fileprivate extension Array where Element == Double {
  func average() -> Double? {
    guard !isEmpty else { return nil }
    return reduce(0, +) / Double(count)
  }
}

struct PerformanceSeries: CustomStringConvertible {
  let label: String
  var values = [Double]()

  init(label: String) {
    self.label = label
  }

  mutating func append(_ value: Double) {
    values.append(value)
  }

  var description: String {
    return "\(label) - avg: \(values.average() ?? 0), max: \(values.max() ?? 0), count: \(values.count)"
  }
}

struct PerformanceGroup<Category>: CustomStringConvertible
    where Category: Hashable & RawRepresentable, Category.RawValue == String {

  let title: String
  var data: [Category: PerformanceSeries] = [:]

  init(title: String) {
    self.title = title
  }

  mutating func append(_ value: Double, to category: Category) {
    data[category, default: PerformanceSeries(label: category.rawValue)].append(value)
  }

  var description: String {
    return "\(title):\n  " + data.values
      .map {series in series.description}
      .joined(separator: "\n  ")
  }
}
