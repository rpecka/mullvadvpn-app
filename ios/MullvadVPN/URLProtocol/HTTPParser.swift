//
//  HTTPParser.swift
//  HTTPParser
//
//  Created by pronebird on 23/07/2021.
//  Copyright © 2021 Mullvad VPN AB. All rights reserved.
//

import Foundation

protocol HTTPParserDelegate: AnyObject {
    func httpParser(_ parser: HTTPParser, didReceiveResponse: HTTPURLResponse)
    func httpParser(_ parser: HTTPParser, didReceiveData: Data)
    func httpParser(_ parser: HTTPParser, didFinishWithError: HTTPParser.Error?)
}

class HTTPParser: NSObject, StreamDelegate {
    weak var delegate: HTTPParserDelegate?

    private var httpHeaderStream = StringStreamIterator<UTF8>(separator: "\r\n")

    private enum State {
        case headers
        case body
    }

    private struct Context {
        var httpVersion: String?
        var httpStatusCode: Int?
        var responseHeaders = [String: String]()

        static let readBufferSize = 256
        var readBuffer = [UInt8](repeating: 0, count: readBufferSize)

        var expectedBodyLength: Int?
        var receivedBodyLength = 0
    }

    enum Error: Swift.Error {
        case streamError(Swift.Error?)
        case cannotParseResponse
    }

    private var state = State.headers
    private var context = Context()
    private let inputStream: InputStream
    private let request: URLRequest

    init(inputStream stream: InputStream, request req: URLRequest) {
        inputStream = stream
        request = req

        super.init()
        stream.delegate = self
    }

    // MARK: - StreamDelegate

    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .hasBytesAvailable:
            while inputStream.hasBytesAvailable {
                let length = inputStream.read(&context.readBuffer, maxLength: Context.readBufferSize)
                if length > 0 {
                    let data = Data(bytes: context.readBuffer, count: length)

                    handleInput(data: data)
                } else {
                    break
                }
            }

        case .endEncountered:
            break

        case .errorOccurred:
            finish(.streamError(inputStream.streamError))

        default:
            break
        }
    }

    // MARK: - Private

    private func handleInput(data: Data) {
        switch state {
        case .headers:
            httpHeaderStream.append(bytes: data)

            while let line = self.httpHeaderStream.next() {
                // HTTP body separator
                if line == "" {
                    state = .body
                    didReceiveHeaders()
                    return
                } else {
                    parseHeader(line)
                }
            }

        case .body:
            context.receivedBodyLength += data.count
            delegate?.httpParser(self, didReceiveData: data)

            if context.expectedBodyLength == context.receivedBodyLength {
                finish(nil)
            }
        }
    }

    private func parseHeader(_ line: String) {
        // Parse the HTTP version/status line if not parsed yet
        if context.httpStatusCode == nil {
            // Parse HTTP/1.1 200 OK
            let split = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
            guard split.count == 3 else {
                finish(.cannotParseResponse)
                return
            }

            // Parse HTTP/1.1
            guard let httpSplit = split.first?.split(separator: "/", maxSplits: 1),
                  let version = httpSplit.last,
                  httpSplit.first?.uppercased() == "HTTP",
                  httpSplit.count == 2 else {
                      finish(.cannotParseResponse)
                      return
                  }

            // Parse status code
            guard let statusCode = Int(split[1]) else {
                finish(.cannotParseResponse)
                return
            }

            context.httpVersion = String(version)
            context.httpStatusCode = statusCode
        } else {
            // Parse header; Header: Value
            let httpHeader = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard let headerKey = httpHeader.first, let headerValue = httpHeader.last, httpHeader.count == 2 else {
                finish(.cannotParseResponse)
                return
            }

            // Drop leading whitespace in value field
            let trimmedHeaderValue = headerValue.drop { ch in
                return ch.isWhitespace
            }

            context.responseHeaders[headerKey.lowercased()] = String(trimmedHeaderValue)
        }
    }

    private func didReceiveHeaders() {
        guard let httpResponse = HTTPURLResponse(
            url: request.url!,
            statusCode: context.httpStatusCode!,
            httpVersion: context.httpVersion!,
            headerFields: context.responseHeaders
        ) else {
            finish(.cannotParseResponse)
            return
        }

        let contentLength = context.responseHeaders["content-length"].flatMap { Int($0) } ?? 0

        context.expectedBodyLength = contentLength

        delegate?.httpParser(self, didReceiveResponse: httpResponse)

        let remainingBytes = httpHeaderStream.getRemainingBytes()
        if !remainingBytes.isEmpty {
            self.handleInput(data: remainingBytes)
        }

        // No body expected?
        if contentLength == 0 {
            finish(nil)
        }
    }

    private func finish(_ error: Error?) {
        state = .headers
        context = Context()
        delegate?.httpParser(self, didFinishWithError: error)
    }
}

extension HTTPParser.Error {
    var urlError: URLError {
        switch self {
        case .streamError(let streamError):
            var userInfo = [String: Any]()
            if let streamError = streamError {
                userInfo[NSUnderlyingErrorKey] = streamError
            }
            return URLError(.networkConnectionLost, userInfo: userInfo)

        case .cannotParseResponse:
            return URLError(.cannotParseResponse)
        }
    }
}
