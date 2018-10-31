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

fileprivate extension Array where Element == TimeInterval {
  func average() -> Double {
    return reduce(0, +) / Double(count)
  }

  func max() -> TimeInterval {
    return reduce(0, Swift.max)
  }
}

final class PerformanceDataCollector: RequestListener, CustomStringConvertible {
  var open = [TimeInterval]()
  var replaceText = [TimeInterval]()

  var description: String {
    return """
    replaceText (avg: \(replaceText.average()), max: \(replaceText.max()), count: \(replaceText.count))
    open (avg: \(open.average()), max: \(open.max()), count: \(open.count))
    """
  }

  func receivedResponse(_ response: String, for request: RequestInfo, after seconds: TimeInterval) {
    switch request {
    case .editorOpen:
      open.append(seconds)
    case .editorReplaceText:
      replaceText.append(seconds)
    default:
      break
    }
  }
}
