//
//  CustomURLProtocol.swift
//  CustomURLProtocol
//
//  Created by pronebird on 23/07/2021.
//  Copyright © 2021 Mullvad VPN AB. All rights reserved.
//

import Foundation
import Network

class CustomURLProtocol: URLProtocol, HTTPParserDelegate {

    private var connection: NWConnection?

    private var readStream: InputStream?
    private var writeStream: OutputStream?
    private var httpParser: HTTPParser?
    private var didSendRequest = false

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canInit(with task: URLSessionTask) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override init(request: URLRequest, cachedResponse: CachedURLResponse?, client: URLProtocolClient?) {
        super.init(request: request, cachedResponse: cachedResponse, client: client)
    }

    deinit {
        readStream?.close()
        readStream?.remove(from: .main, forMode: .common)
        
        writeStream?.close()
        writeStream?.remove(from: .main, forMode: .common)
    }

    override func startLoading() {
        let hostname = request.url?.host
        let host = NWEndpoint.Host.name(hostname!, nil)
        let port: NWEndpoint.Port = request.url?.scheme?.uppercased() == "HTTPS" ? .https : .http

        connection = NWConnection(host: host, port: port, using: createTLSParameters(queue: .main))

        guard let connection = connection else {
            self.client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
            return
        }

        Stream.getBoundStreams(withBufferSize: 256, inputStream: &readStream, outputStream: &writeStream)
        readStream?.schedule(in: .main, forMode: .common)
        writeStream?.schedule(in: .main, forMode: .common)

        httpParser = HTTPParser(inputStream: readStream!, request: self.request)
        httpParser?.delegate = self

        readStream?.open()
        writeStream?.open()

        connection.stateUpdateHandler = { [weak self] (state) in
            self?.handleStateChange(state: state)
        }

        connection.start(queue: .main)
    }

    override func stopLoading() {
        connection?.cancel()
    }

    private func createTLSParameters(queue: DispatchQueue) -> NWParameters {
        let options = NWProtocolTLS.Options()

        sec_protocol_options_set_verify_block(options.securityProtocolOptions, { (sec_protocol_metadata, sec_trust, sec_protocol_verify_complete) in
            let trust = sec_trust_copy_ref(sec_trust).takeRetainedValue()
            var error: CFError?

            let isVerified = SecTrustEvaluateWithError(trust, &error)
            sec_protocol_verify_complete(isVerified)
        }, queue)

        return NWParameters(tls: options)
    }

    private func sendURLRequest() {
        let payload = HTTPURLRequestSerializer.serialize(request: request)

        connection?.send(content: payload, completion: .contentProcessed({ error in
            if let error = error {
                self.closeWithError(error)
            } else {
                self.readConnection()
            }
        }))
    }

    private func readConnection() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 256, completion: { content, contentContext, isComplete, error in
            if let error = error {
                self.closeWithError(error)
            } else {
                if let data = content, !data.isEmpty {
                    data.withUnsafeBytes { buffer in
                        let uint8Buffer = buffer.bindMemory(to: UInt8.self)

                        _ = self.writeStream?.write(uint8Buffer.baseAddress!, maxLength: buffer.count)
                    }
                }

                if !isComplete {
                    self.readConnection()
                }
            }
        })
    }

    private func handleStateChange(state: NWConnection.State) {
        switch state {
        case .failed(let error):
            closeWithError(makeURLError(.networkConnectionLost, underlyingError: error))

        case .ready:
            if !didSendRequest {
                didSendRequest = true
                sendURLRequest()
            }

        case .cancelled:
            closeWithError(makeURLError(.cancelled, underlyingError: nil))

        default:
            break
        }
    }

    private func makeURLError(_ errorCode: URLError.Code, underlyingError: Error?) -> URLError {
        var userInfo: [String: Any] = [:]
        if let underlyingError = underlyingError {
            userInfo[NSUnderlyingErrorKey] = underlyingError
        }

        return URLError(errorCode, userInfo: userInfo)
    }

    private func closeWithError(_ error: Error) {
        connection?.cancel()

        client?.urlProtocol(self, didFailWithError: error)
    }

    // MARK: - HTTPParserDelegate

    func httpParser(_ parser: HTTPParser, didReceiveResponse response: HTTPURLResponse) {
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }

    func httpParser(_ parser: HTTPParser, didReceiveData data: Data) {
        client?.urlProtocol(self, didLoad: data)
    }

    func httpParser(_ parser: HTTPParser, didFinishWithError error: HTTPParser.Error?) {
        if let error = error {
            client?.urlProtocol(self, didFailWithError: error.urlError)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

}

