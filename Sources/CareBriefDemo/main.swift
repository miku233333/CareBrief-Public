import CareBriefCore
import Foundation

#if canImport(Darwin)
  import Darwin
#else
  import Glibc
#endif

private let sampleText = """
  您需於 2026 年 8 月 15 日上午 9 時到威爾斯親王醫院內科門診覆診，覆診前禁食 8 小時，請攜帶身份證及覆診紙。
  如有查詢，請致電 2632 2211。
  """

private enum DemoError: LocalizedError {
  case invalidArguments
  case invalidUTF8

  var errorDescription: String? {
    switch self {
    case .invalidArguments:
      return "Usage: carebrief-demo [--file PATH | --stdin]"
    case .invalidUTF8:
      return "Input must be valid UTF-8 text."
    }
  }
}

private func inputText(arguments: [String]) throws -> String {
  guard let first = arguments.first else { return sampleText }

  switch first {
  case "--stdin":
    guard arguments.count == 1 else { throw DemoError.invalidArguments }
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard let text = String(data: data, encoding: .utf8) else {
      throw DemoError.invalidUTF8
    }
    return text
  case "--file":
    guard arguments.count == 2 else { throw DemoError.invalidArguments }
    return try String(contentsOfFile: arguments[1], encoding: .utf8)
  case "--help", "-h":
    print("Usage: carebrief-demo [--file PATH | --stdin]")
    exit(EXIT_SUCCESS)
  default:
    throw DemoError.invalidArguments
  }
}

do {
  let text = try inputText(arguments: Array(CommandLine.arguments.dropFirst()))
  let document = SourceDocument(
    id: UUID(uuidString: "6BCFCB2F-705B-4EB7-97D0-B9EA9C6C8B71")!,
    text: text,
    language: .mixed
  )
  let result = RuleBasedActionExtractor().extract(from: document)
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  let data = try encoder.encode(result)
  print(String(decoding: data, as: UTF8.self))
} catch {
  let message = "carebrief-demo: \(error.localizedDescription)\n"
  FileHandle.standardError.write(Data(message.utf8))
  exit(EXIT_FAILURE)
}
