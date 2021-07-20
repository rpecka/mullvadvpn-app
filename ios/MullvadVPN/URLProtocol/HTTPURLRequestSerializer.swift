//
//  HTTPURLRequestSerializer.swift
//  HTTPURLRequestSerializer
//
//  Created by pronebird on 23/07/2021.
//  Copyright © 2021 Mullvad VPN AB. All rights reserved.
//

import Foundation

enum HTTPURLRequestSerializer {}

extension HTTPURLRequestSerializer {
    static func serialize(request: URLRequest) -> Data {
        let httpMethod = request.httpMethod?.uppercased() ?? "GET"
        let serverPath = request.url?.path ?? "/"

        var bodyData: Data?

        var httpRequest = [
            "\(httpMethod) \(serverPath) HTTP/1.1"
        ]

        if let hostname = request.url?.host {
            httpRequest.append("Host: \(hostname)")
        }
        if let httpBody = request.httpBody {
            httpRequest.append("Content-Length: \(httpBody.count)")
            bodyData = httpBody
        }

        if request.httpBodyStream != nil {
            fatalError("Unsupported HTTP body stream!")
        }

        let headers = request.allHTTPHeaderFields ?? [:]
        for (header, value) in headers {
            httpRequest.append("\(header): \(value)")
        }

        var requestData = httpRequest.joined(separator: "\r\n")
            .appending("\r\n\r\n")
            .data(using: .utf8)!

        if let bodyData = bodyData {
            requestData.append(bodyData)
        }

        return requestData
    }
}
