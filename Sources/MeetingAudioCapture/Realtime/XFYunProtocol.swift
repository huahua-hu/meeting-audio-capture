import Foundation

enum XFYunServerEvent: Equatable, Sendable {
    case started
    case partial(startTime: TimeInterval, endTime: TimeInterval, text: String)
    case final(startTime: TimeInterval, endTime: TimeInterval, text: String)
    case failed(code: Int, message: String)
}

enum XFYunProtocolParser {
    enum ParserError: Error {
        case malformedEnvelope
        case malformedResult
        case unsupportedAction(String)
    }

    private struct Envelope: Decodable {
        let action: String
        let code: String?
        let desc: String?
        let data: String?
    }

    private struct Result: Decodable {
        struct Container: Decodable {
            let st: Recognition
        }

        struct Recognition: Decodable {
            struct WordSegment: Decodable {
                struct Candidate: Decodable {
                    let w: String
                }

                let cw: [Candidate]
            }

            let bg: String
            let ed: String
            let type: String
            let rt: [ResultGroup]

            struct ResultGroup: Decodable {
                let ws: [WordSegment]
            }
        }

        let cn: Container
    }

    static func parse(_ message: String) throws -> XFYunServerEvent {
        guard let envelopeData = message.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: envelopeData) else {
            throw ParserError.malformedEnvelope
        }

        switch envelope.action {
        case "started":
            return .started
        case "error":
            return .failed(code: Int(envelope.code ?? "") ?? -1, message: envelope.desc ?? "Unknown error")
        case "result":
            guard let resultString = envelope.data,
                  let resultData = resultString.data(using: .utf8),
                  let result = try? JSONDecoder().decode(Result.self, from: resultData) else {
                throw ParserError.malformedResult
            }
            let recognition = result.cn.st
            let text = recognition.rt
                .flatMap(\.ws)
                .compactMap(\.cw.first?.w)
                .joined()
            let start = (Double(recognition.bg) ?? 0) / 1_000
            let end = (Double(recognition.ed) ?? 0) / 1_000
            if recognition.type == "0" {
                return .final(startTime: start, endTime: end, text: text)
            }
            return .partial(startTime: start, endTime: end, text: text)
        default:
            throw ParserError.unsupportedAction(envelope.action)
        }
    }
}
