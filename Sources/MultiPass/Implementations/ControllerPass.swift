//
//  ControllerPass.swift
//
//
//  Created by John Haney on 7/6/24.
//

import Foundation
import GameController

class ControllerPass {
    typealias ID = UUID
    typealias FromID = UUID
    typealias Session = GCController
    
    var id: UUID
    var connectionState: ConnectionState
    var controller: GCController
    var displayName: String = ""
    
    let participant: MultiPass.Participant
    
    required init(_ fromID: UUID, session: GCController, participant: MultiPass.Participant) {
        self.controller = session
        self.id = fromID
        self.connectionState = .connected
        self.participant = participant
    }
}
