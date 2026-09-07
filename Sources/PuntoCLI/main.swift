import Foundation
import PuntoCore

// One request per invocation. Only stdin/stdout carry text; no clipboard or GUI access.
private struct CycleSession: Codable {
    let originalWord: String
    let leftBuffer: String
    let rightBuffer: String
    let targetLanguage: PuntoLanguage
}

private struct Request: Decodable {
    let version: Int
    let leftBuffer: String
    let rightBuffer: String
    let session: CycleSession?
}

private struct Response: Encodable {
    let version = 1
    let leftBuffer: String
    let rightBuffer: String
    let session: CycleSession?
}

private func exactlyEqual(_ lhs: String, _ rhs: String) -> Bool {
    lhs.utf8.elementsEqual(rhs.utf8)
}

private func transform(_ request: Request) throws -> Response {
    guard request.version == 1,
          !request.leftBuffer.contains("\0"), !request.rightBuffer.contains("\0") else {
        throw ProtocolError.invalidRequest
    }
    guard let word = TextScanner.scanLastWord(in: request.leftBuffer) else {
        return Response(leftBuffer: request.leftBuffer, rightBuffer: request.rightBuffer, session: nil)
    }
    let engine = PuntoEngine()
    let settings = PuntoSettings(switchingMode: .sequential)
    var originalWord = word.word
    if let session = request.session,
       exactlyEqual(session.leftBuffer, request.leftBuffer),
       exactlyEqual(session.rightBuffer, request.rightBuffer),
       session.originalWord.utf16.count <= 300 {
        // Recover the private engine cycle by replaying at most one complete cycle.
        // The session is scoped by the caller to one ZLE input and exact caret buffers.
        var replayed = session.originalWord
        var matched = false
        for _ in 0..<PuntoLanguage.allCases.count {
            let result = engine.convertLayout(replayed, settings: settings)
            replayed = result.replacementText
            if exactlyEqual(replayed, word.word), result.targetLanguage == session.targetLanguage {
                matched = true
                break
            }
        }
        if matched { originalWord = session.originalWord } else { engine.resetContext() }
    }
    let result = engine.convertLayout(word.word, settings: settings)
    var left = request.leftBuffer
    left.replaceSubrange(word.wordRange, with: result.replacementText)
    let session = result.targetLanguage.map {
        CycleSession(originalWord: originalWord, leftBuffer: left,
                     rightBuffer: request.rightBuffer, targetLanguage: $0)
    }
    return Response(leftBuffer: left, rightBuffer: request.rightBuffer, session: session)
}

private enum ProtocolError: Error { case invalidRequest }

do {
    // Bounded read rejects overlarge input without accumulating an unbounded stream.
    let input = FileHandle.standardInput.readData(ofLength: 1_048_577)
    guard input.count <= 1_048_576 else { throw ProtocolError.invalidRequest }
    let request = try JSONDecoder().decode(Request.self, from: input)
    let output = try JSONEncoder().encode(transform(request))
    FileHandle.standardOutput.write(output)
    FileHandle.standardOutput.write(Data([10]))
} catch {
    FileHandle.standardError.write(Data("punto-transform: invalid request or transformation failed\n".utf8))
    exit(1)
}
