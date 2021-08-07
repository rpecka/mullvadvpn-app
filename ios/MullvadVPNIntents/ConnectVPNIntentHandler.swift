//
//  ConnectVPNIntentHandler.swift
//  MullvadVPNIntents
//
//  Created by Russell Pecka on 8/5/21.
//  Copyright © 2021 Mullvad VPN AB. All rights reserved.
//

import Foundation
import Intents


final class ConnectVPNIntentHandler: NSObject, ConnectVPNIntentHandling {
    func confirm(intent: ConnectVPNIntent, completion: @escaping (ConnectVPNIntentResponse) -> Void) {
        guard let location = intent.location else {
            completion(.init(code: .missingLocation, userActivity: nil))
            return
        }
        TunnelManager.shared.loadTunnel(accountToken: Account.shared.token) { result in
            switch result {
            case .success:
                completion(.success(location: location))
            case .failure:
                completion(.init(code: .notLoggedIn, userActivity: nil))
            }
        }
    }

    @available(iOSApplicationExtension 13.0, *)
    func resolveLocation(for intent: ConnectVPNIntent, with completion: @escaping (IntentLocationResolutionResult) -> Void) {
        guard let location = intent.location else {
            completion(.confirmationRequired(with: nil))
            return
        }
        RelayCache.shared.read { result in
            switch result {
            case .success(let cachedRelays):
                print(cachedRelays.relays.locations)
                completion(.success(with: location))
            case .failure(_):
                completion(.confirmationRequired(with: location))
            }
        }
    }

    @available(iOSApplicationExtension 14.0, *)
    func provideLocationOptionsCollection(for intent: ConnectVPNIntent, searchTerm: String?, with completion: @escaping (INObjectCollection<IntentLocation>?, Error?) -> Void) {
        RelayCache.shared.read { result in
            switch result {
            case .failure(let error):
                completion(nil, error)
            case .success(let cachedRelays):
                var processedLocations = Set<RelayLocation>()
                let locations: [IntentLocation] = cachedRelays.relays.wireguard.relays.reduce(into: []) {
                    guard let relayLocation = RelayLocation(dashSeparatedString: $1.location),
                          let serverLocation = cachedRelays.relays.locations[$1.location] else {
                        return
                    }
                    $0.append(contentsOf: (relayLocation.ascendants + [relayLocation]).compactMap {
                        guard !processedLocations.contains($0) else {
                            return nil
                        }
                        processedLocations.insert($0)

                        var location: IntentLocation
                        switch $0 {
                        case .country:
                            location = .init(identifier: $0.stringRepresentation, display: serverLocation.country)
                        case .city:
                            location = IntentLocation(identifier: $0.stringRepresentation, display: serverLocation.city)
                            location.country = serverLocation.country
                        case .hostname:
                            location = IntentLocation(identifier: $0.stringRepresentation, display: $0.stringRepresentation)
                            location.country = serverLocation.country
                            location.city = serverLocation.city
                        }
                        return location
                    })
                }

                let results: [IntentLocation]
                if let searchTerm = searchTerm?.lowercased() {
                    results = locations.filter { location in
                        location.identifier?.lowercased().contains(searchTerm) ?? false || location.displayString.lowercased().contains(searchTerm) || location.country?.lowercased().contains(searchTerm) ?? false || location.city?.lowercased().contains(searchTerm) ?? false
                    }
                } else {
                    results = locations
                }
                completion(.init(items: results), nil)
            }
        }
    }

    func handle(intent: ConnectVPNIntent, completion: @escaping (ConnectVPNIntentResponse) -> Void) {
        guard let location = intent.location else {
            completion(.init(code: .missingLocation, userActivity: nil))
            return
        }
        guard let relayLocation = RelayLocation(dashSeparatedString: location.identifier!) else {
            completion(.init(code: .invalidLocation, userActivity: nil))
            return
        }
        TunnelManager.shared.setRelayConstraints(.init(location: .only(relayLocation))) { [weak self] result in
            switch result {
            case .failure(let error):
                switch error {
                case .missingAccount:
                    completion(.init(code: .notLoggedIn, userActivity: nil))
                default:
                    completion(.failure(location: location))
                }
            case .success():
                self?.connectTunnel(location: location, completion: completion)
            }
        }
    }

    // MARK: - Private

    private func connectTunnel(location: IntentLocation, completion: @escaping (ConnectVPNIntentResponse) -> Void) {
        TunnelManager.shared.startTunnel { result in
            switch result {
            case .success():
                completion(.success(location: location))
            case .failure(let error):
                completion(.failure(location: location))
            }
        }
    }
}
