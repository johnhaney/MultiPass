//
//  File.swift
//  
//
//  Created by John Haney on 7/6/24.
//

import MultipeerConnectivity

class MultipeerPass {
    var session: MCSession
    var peerID: MCPeerID
    
    var displayName: String { peerID.displayName }
    var connectionState: ConnectionState = .disconnected
    
    required init(_ fromID: MCPeerID, session: MCSession) {
        self.session = session
        self.peerID = fromID
    }
}
