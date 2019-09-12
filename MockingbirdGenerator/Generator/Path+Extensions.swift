//
//  Path+Extensions.swift
//  MockingbirdGenerator
//
//  Created by Andrew Chang on 9/3/19.
//

import Foundation
import PathKit

enum WriteUtf8StringFailure: Error, CustomStringConvertible {
  case streamCreationFailure(path: Path)
  case dataEncodingFailure
  case streamWritingFailure(error: Error?)
  
  var description: String {
    switch self {
    case .streamCreationFailure(let path): return "Unable to create output stream to \(path)"
    case .dataEncodingFailure: return "Unable to encode data to UTF8"
    case .streamWritingFailure(let error): return "Failed to write to output stream, error: \(error?.localizedDescription ?? "(nil)")"
    }
  }
}

private class FileManagerMoveDelegate: NSObject, FileManagerDelegate {
  func fileManager(_ fileManager: FileManager, shouldMoveItemAt srcURL: URL, to dstURL: URL)
    -> Bool { return true }
  
  func fileManager(_ fileManager: FileManager,
                   shouldProceedAfterError error: Error,
                   movingItemAt srcURL: URL,
                   to dstURL: URL)
    -> Bool { return true }
  
  static let shared = FileManagerMoveDelegate()
}

struct PartialFileContents {
  let contents: String?
  let substructure: [PartialFileContents]
  let delimiter: String?
  let footer: String?
  
  var isEmpty: Bool {
    return contents?.isEmpty == true && substructure.isEmpty
  }
  
  init(contents: String? = nil,
       substructure: [PartialFileContents] = [],
       delimiter: String? = nil,
       footer: String? = nil) {
    self.contents = contents
    self.substructure = substructure
    self.delimiter = delimiter
    self.footer = footer
  }
}

extension Path {
  /// Writes a set of UTF-8 strings to disk without validating the encoding.
  ///
  /// - Note: This is ~15-20% faster compared to String.write(toFile:atomically:encoding:)
  ///
  /// - Parameters:
  ///   - fileContents: An array of partial content objects containing strings to write to disk.
  ///   - atomically: Whether to write to a temporary file first, then atomically move it to the
  ///     current path, replacing any existing file.
  /// - Throws: A `BufferedWriteFailure` if an error occurs.
  func writeUtf8Strings(_ fileContents: PartialFileContents, atomically: Bool = true) throws {
    let tmpFilePath = (atomically ? try Path.uniqueTemporary() + lastComponent : self)
    guard let outputStream = OutputStream(toFileAtPath: "\(tmpFilePath.absolute())", append: true)
      else { throw WriteUtf8StringFailure.streamCreationFailure(path: tmpFilePath) }
    outputStream.open()
    defer { outputStream.close() }
    
    let write: (String) throws -> Void = { contents in
      let count = contents.utf8CString.count-1 // Last character is a `Nul` character in a C string.
      guard let data = contents.utf8CString.withUnsafeBytes({
        $0.bindMemory(to: UInt8.self).baseAddress
      }) else { throw WriteUtf8StringFailure.dataEncodingFailure }
      
      let written = outputStream.write(data, maxLength: count)
      guard written == count else {
        throw WriteUtf8StringFailure.streamWritingFailure(error: outputStream.streamError)
      }
    }
    
    var writePartial: ((PartialFileContents) throws -> Void)!
    writePartial = { partial in
      if let contents = partial.contents { try write(contents) }
      var isFirstElement = true
      for structure in partial.substructure {
        if !isFirstElement, let delimiter = partial.delimiter { try write(delimiter) }
        isFirstElement = false
        try writePartial(structure)
      }
      if let footer = partial.footer { try write(footer) }
    }
    try writePartial(fileContents)
    
    guard atomically else { return }
    let tmpFileURL = URL(fileURLWithPath: "\(tmpFilePath.absolute())", isDirectory: false)
    let outputFileURL = URL(fileURLWithPath: "\(absolute())", isDirectory: false)
    
    FileManager.default.delegate = FileManagerMoveDelegate.shared
    _ = try FileManager.default.moveItem(at: tmpFileURL, to: outputFileURL)
  }
}
