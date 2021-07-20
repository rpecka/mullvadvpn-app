//
//  StringStreamIterator.swift
//  MullvadVPN
//
//  Created by pronebird on 17/08/2020.
//  Copyright © 2020 Mullvad VPN AB. All rights reserved.
//

import Foundation

class StringStreamIterator<Codec>: IteratorProtocol where Codec: UnicodeCodec {
    let separator: String
    var frame: [Character] = []

    private var string = ""
    private var data = [Codec.CodeUnit]()
    private var parser = Codec.ForwardParser()

    init(separator: String) {
        self.separator = separator
    }

    init(separator: Character) {
        self.separator = String(separator)
    }

    func append<S>(bytes: S) where S: Sequence, S.Element == Codec.CodeUnit {
        data.append(contentsOf: bytes)
    }

    func getRemainingBytes() -> Data {
        return data.withUnsafeBufferPointer { bufferPointer in
            return Data(buffer: bufferPointer)
        }
    }

    func next() -> String? {
        var dataIterator = data.makeIterator()
        var bytesRead = 0

        defer {
            if bytesRead > 0 {
                data.removeSubrange(..<bytesRead)
            }
        }

        let frameLength = separator.unicodeScalars.count

        while case .valid(let encodedScalar) = parser.parseScalar(from: &dataIterator) {
            let unicodeScalar = Codec.decode(encodedScalar)
            let character = Character(unicodeScalar)

            bytesRead += encodedScalar.count

            if frame.count < frameLength {
                frame.append(character)
            }

            if frame.count == frameLength {
                if String(frame) == separator {
                    let returnString = string
                    string = ""
                    frame.removeAll()

                    return returnString
                } else {
                    string.append(frame.removeFirst())
                }
            }
        }

        return nil
    }
}
