//
//  IntentHandler.swift
//  MullvadVPNIntents
//
//  Created by Russell Pecka on 8/5/21.
//  Copyright © 2021 Mullvad VPN AB. All rights reserved.
//

import Intents

class IntentHandler: INExtension {

    #if targetEnvironment(simulator)
    private let simulatorTunnelProvider = SimulatorTunnelProviderHost()
    #endif

    override init() {
        #if targetEnvironment(simulator)
        // Configure mock tunnel provider on simulator
        SimulatorTunnelProvider.shared.delegate = simulatorTunnelProvider
        #endif

        super.init()
    }
    
    override func handler(for intent: INIntent) -> Any {
        guard intent is ConnectVPNIntent else {
            return self
        }

        return ConnectVPNIntentHandler()
    }
    
}
