//
//  ApplicationConfiguration.swift
//  MullvadVPN
//
//  Created by pronebird on 05/06/2019.
//  Copyright © 2019 Mullvad VPN AB. All rights reserved.
//

import Foundation

enum ApplicationConfiguration {}

extension ApplicationConfiguration {

    /// The application group identifier used for sharing application preferences between processes
    static let securityGroupIdentifier = "group.xyz.pecka.MullvadVPN"

    /// The application identifier for the PacketTunnel extension
    static let packetTunnelExtensionIdentifier = "xyz.pecka.MullvadVPN.PacketTunnel"

    /// Container URL for security group
    static var containerURL: URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.securityGroupIdentifier)
    }

    /// The main application log file located in a shared container
    static var mainApplicationLogFileURL: URL? {
        return Self.containerURL?.appendingPathComponent("Logs/net.mullvad.MullvadVPN.log", isDirectory: false)
    }

    /// The packet tunnel log file located in a shared container
    static var packetTunnelLogFileURL: URL? {
        return Self.containerURL?.appendingPathComponent("Logs/net.mullvad.MullvadVPN.PacketTunnel.log", isDirectory: false)
    }

    /// All log files located in a shared container
    static var logFileURLs: [URL] {
        return [mainApplicationLogFileURL, packetTunnelLogFileURL].compactMap { $0 }
    }
}
