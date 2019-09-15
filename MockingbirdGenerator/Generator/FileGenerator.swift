//
//  FileGenerator.swift
//  MockingbirdCli
//
//  Created by Andrew Chang on 8/5/19.
//  Copyright © 2019 Bird Rides, Inc. All rights reserved.
//

// swiftlint:disable leading_whitespace

import Foundation
import PathKit
import os.log

class FileGenerator {
  let mockableTypes: [MockableType]
  let moduleName: String
  let imports: Set<String>
  let outputPath: Path
  let shouldImportModule: Bool
  let preprocessorExpression: String?
  let onlyMockProtocols: Bool
  let disableSwiftlint: Bool
  
  init(_ mockableTypes: [MockableType],
       moduleName: String,
       imports: Set<String>,
       outputPath: Path,
       preprocessorExpression: String?,
       shouldImportModule: Bool,
       onlyMockProtocols: Bool,
       disableSwiftlint: Bool) {
    self.mockableTypes = onlyMockProtocols ?
      mockableTypes.filter({ $0.kind == .protocol }) :
      mockableTypes
    self.moduleName = moduleName
    self.imports = imports
    self.outputPath = outputPath
    self.preprocessorExpression = preprocessorExpression
    self.shouldImportModule = shouldImportModule
    self.onlyMockProtocols = onlyMockProtocols
    self.disableSwiftlint = disableSwiftlint
  }
  
  var outputFilename: String {
    return outputPath.components.last ?? "MockingbirdMocks.generated.swift"
  }
  
  private func generateFileHeader() -> PartialFileContent {
    let swiftlintDirective = disableSwiftlint ? "\n// swiftlint:disable all\n": ""
    
    let preprocessorDirective: String
    if let expression = preprocessorExpression {
      preprocessorDirective = "\n#if \(expression)\n"
    } else {
      preprocessorDirective = ""
    }
    
    let moduleImports = (
      imports.union(["import Foundation", "@testable import Mockingbird"]).union(
        shouldImportModule ? ["@testable import \(moduleName)"] : []
      )
    ).sorted()
    
    return PartialFileContent(contents: """
    //
    //  \(outputFilename)
    //  \(moduleName)
    //
    //  Generated by Mockingbird v\(mockingbirdVersion.shortString).
    //  DO NOT EDIT
    //
    \(swiftlintDirective)\(preprocessorDirective)
    \(moduleImports.joined(separator: "\n"))
    
    """)
  }
  
  private func generateFileBody() -> PartialFileContent {
    guard !mockableTypes.isEmpty else { return PartialFileContent(contents: "") }
    let operations = mockableTypes
      .sorted(by: <)
      .map({ RenderMockableTypeOperation(mockableType: $0, moduleName: moduleName) })
    let queue = OperationQueue.createForActiveProcessors()
    queue.addOperations(operations, waitUntilFinished: true)
    let substructure = [PartialFileContent(contents: synchronizedClass),
                        PartialFileContent(contents: genericTypesStaticMocks)]
      + operations.map({ PartialFileContent(contents: $0.result.renderedContents) })
    return PartialFileContent(substructure: substructure, delimiter: "\n\n")
  }
  
  private func generateFileFooter() -> PartialFileContent {
    guard preprocessorExpression != nil else { return .empty }
    return PartialFileContent(contents: "\n#endif")
  }
  
  func generate() -> PartialFileContent {
    return PartialFileContent(contents: nil,
                               substructure: [generateFileHeader(),
                                              generateFileBody(),
                                              generateFileFooter()].filter({ !$0.isEmpty }),
                               delimiter: "\n",
                               footer: "\n")
  }
  
  private var synchronizedClass: String {
    return """
    private class Synchronized<T> {
      private var internalValue: T
      fileprivate var value: T {
        get {
          lock.wait()
          defer { lock.signal() }
          return internalValue
        }
    
        set {
          lock.wait()
          defer { lock.signal() }
          internalValue = newValue
        }
      }
      private let lock = DispatchSemaphore(value: 1)
    
      fileprivate init(_ value: T) {
        self.internalValue = value
      }
    
      fileprivate func update(_ block: (inout T) throws -> Void) rethrows {
        lock.wait()
        defer { lock.signal() }
        try block(&internalValue)
      }
    }
    """
  }
  
  private var genericTypesStaticMocks: String {
    return "private var genericTypesStaticMocks = Synchronized<[String: Mockingbird.StaticMock]>([:])"
  }
}
