//
//  MultipeerConnector.swift
//
//
//  Created by John Haney on 7/6/24.
//

import Foundation
import MultipeerConnectivity
import OSLog

fileprivate let logger = Logger(subsystem: "com.appsfromouterspace.MultiPass", category: "Multipeer")

class MultipeerConnector: MultiConnector, ObservableObject {
    let id: UUID = UUID()
    @MainActor var mapping: [MCPeerID: MultiPass.Participant] = [:]
    @MainActor var router: [MultiPass.Participant : MCPeerID] = [:]
    
    private let myPeerID: MCPeerID
    private let delegate: Delegate
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser
    private let session: MCSession

    var multipass: MultiPass

    init(multipass: MultiPass, serviceName: String, peerID: UUID) {
        self.multipass = multipass
        myPeerID = MCPeerID(displayName: peerID.uuidString)
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceName)
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceName)
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .optional)
        delegate = Delegate(localID: peerID)
        delegate.manager = self
        delegate.session = session
        session.delegate = delegate
        print("JMH: init \(id)")
    }
    
    deinit {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        advertiser.delegate = nil
        browser.delegate = nil
    }
}

extension MultipeerConnector {
    @MainActor func send(data: Data, reliable: Bool = true) {
        guard !delegate.peerState.isEmpty else {
//            logger.debug("Multipeer no state, not sending \(data.count) byte message")
            return
        }
        let peers = delegate.peerState.compactMap({
            if $0.key != myPeerID,
               $0.value == .connected {
                return $0.key
            } else {
                return nil
            }
        })
        guard !peers.isEmpty else {
//            logger.debug("Multipeer no peers, not sending \(data.count) byte message")
            return
        }
        do {
            try session.send(
                data,
                toPeers: peers,
                with: reliable ? .reliable : .unreliable
            )
            logger.debug("Sent \(data.count) byte message")
        } catch {
            logger.error("Multipeer did not send \(data.count) byte message: \(error.localizedDescription)")
        }
    }
    
    @MainActor func receive(data: Data, from: MCPeerID) throws {
        let onParticipant = { participant in
            self.router[participant] = from
            self.mapping[from] = participant
        }
        try MultiPass.receive(data: data, connector: self, participantCallback: { participant in
            onParticipant(participant)
        })
    }
}

extension MultipeerConnector {
    fileprivate class Delegate: NSObject {
        fileprivate let logger = Logger(subsystem: "com.appsfromouterspace.MultiPass", category: "Multipeer")
        @MainActor var peerState: [MCPeerID: MCSessionState] = [:]
        @MainActor var peerSetupState: [MCPeerID: SetupState] = [:]
        var manager: MultipeerConnector!
        var session: MCSession!
        var localID: UUID
        enum SetupState {
            case accepted
            case invited
            case connected
        }
        @MainActor func handle(_ data: Data, from: MCPeerID) {
            do {
                try manager.receive(data: data, from: from)
            } catch {
                logger.error("Error receiving \(data.count) byte message from \(from): \(error.localizedDescription)")
            }
        }
        
        init(localID: UUID) {
            self.localID = localID
        }
    }
}

extension MultipeerConnector {
    private func startBrowsing() {
        logger.debug("start browsing")
        browser.delegate = delegate
        browser.startBrowsingForPeers()
    }

    private func startAdvertising() {
        logger.debug("start advertising")
        advertiser.delegate = delegate
        advertiser.startAdvertisingPeer()
    }

    public func start() {
        logger.debug("start")
        startAdvertising()
        startBrowsing()
    }
    
    public func stop() {
        logger.debug("stop")
        browser.stopBrowsingForPeers()
        browser.delegate = nil

        advertiser.stopAdvertisingPeer()
        advertiser.delegate = nil
    }
    
    @MainActor func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .notConnected:
            delegate.peerState.removeValue(forKey: peerID)
            logger.debug("peer did change state - disconnected")
            delegate.peerSetupState.removeValue(forKey: peerID)
            if let participant = self.mapping[peerID] {
                multipass.remove(remote: participant)
                self.mapping.removeValue(forKey: peerID)
                self.router.removeValue(forKey: participant)
            }
        case .connecting:
            logger.debug("peer did change state - connecting")
        case .connected:
            logger.debug("peer did change state - connected")
            delegate.peerSetupState[peerID] = .connected
            do {
                let data = try multipass.helloMessage(again: mapping.keys.contains(peerID))
                try session.send(data, toPeers: [peerID], with: .reliable)
            } catch {
                logger.debug("peer could not send hello: \(error.localizedDescription)")
            }
        @unknown default:
            logger.debug("peer did change state - ???")
            break
        }
    }
}

extension MultipeerConnector.Delegate {
    @MainActor func handleFound(peerID: MCPeerID) -> Bool {
        logger.debug("Found peer \(peerID)")
        switch peerSetupState[peerID] {
        case .accepted:
            logger.debug("Found peer, peerSetupState already accepted")
            return false
        case .invited:
            logger.debug("Found peer, peerSetupState already invited")
            return false
        case .connected:
            logger.debug("Found peer, peerSetupState already connected")
            return false
        case .none:
            logger.debug("Found new peer, no peerSetupState")
            break
        }
        switch peerState[peerID] {
        case .connected:
            logger.debug("Found peer, peerState already connected")
            peerSetupState[peerID] = .connected
            return false
        case .connecting:
            logger.debug("Found peer, peerState connecting")
            break
        case .notConnected, .none:
            logger.debug("Found peer, peerState not connected")
            break
        }
        peerSetupState[peerID] = .invited
        logger.debug("Found peer, inviting... \(self.localID) \(peerID.displayName)")
        logger.debug("Found peer & invited")
        return true
    }
    
    @MainActor func handleInvite(from peerID: MCPeerID) -> Bool {
        switch peerSetupState[peerID] {
        case .accepted:
            logger.debug("invited, peerSetupState already accepted")
            return false
        case .invited:
            logger.debug("invited, peerSetupState already invited")
            return false
        case .connected:
            logger.debug("invited, peerSetupState already connected")
            return false
        case .none:
            break
        }
        switch peerState[peerID] {
        case .connected:
            logger.debug("invited, peerState already connected")
            peerSetupState[peerID] = .connected
            return false
        case .connecting:
            break
        case .notConnected, .none:
            break
        }
        peerSetupState[peerID] = .accepted
        logger.debug("invited, accepting...")
        return true
    }
}

extension MultipeerConnector.Delegate: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        Task {
            let invite = await handleFound(peerID: peerID)
            if invite {
                browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10.0)
            }
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        logger.debug("Lost peer \(peerID)")
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: any Error) {
        logger.error("did not start browsing because: \(error.localizedDescription)")
    }
}

extension MultipeerConnector.Delegate: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task {
            let accept = await handleInvite(from: peerID)
            if accept {
                invitationHandler(true, session)
            } else {
                invitationHandler(false, nil)
            }
        }
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: any Error) {
        Logger(subsystem: "com.appsfromouterspace.MultiPass", category: "MultipeerAdvertiser").error("Did not start advertising \(error.localizedDescription)")
    }
}

extension MultipeerConnector.Delegate: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task {
            await handle(session, peer: peerID, state: state)
        }
    }
    
    @MainActor func handle(_ session: MCSession, peer peerID: MCPeerID, state: MCSessionState) {
        peerState[peerID] = state
        self.manager.session(session, peer: peerID, didChange: state)
        switch state {
        case .notConnected:
            logger.debug("peer \(peerID) not connected")
//            peerState.removeValue(forKey: peerID)
            peerSetupState.removeValue(forKey: peerID)
        case .connecting:
            logger.debug("peer \(peerID) connecting...")
        case .connected:
            logger.debug("peer \(peerID) connected")
            peerSetupState[peerID] = .connected
        @unknown default:
            logger.warning("peer \(peerID) UNKNOWN STATE \(state.rawValue)")
            peerSetupState.removeValue(forKey: peerID)
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        logger.debug("data \(data.count) from \(peerID)")
        Task {
            await handle(data, from: peerID)
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        logger.debug("stream [\(streamName)] from \(peerID)")
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        logger.debug("resource \(resourceName) from \(peerID) started")
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: (any Error)?) {
        logger.debug("resource \(resourceName) from \(peerID) finished")
    }
    
    func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) {
        logger.debug("certificate from \(peerID) \(certificate ?? [])")
        certificateHandler(true)
    }
}
