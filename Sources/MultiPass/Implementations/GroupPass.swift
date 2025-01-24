//
//  GroupPass.swift
//
//
//  Created by John Haney on 7/6/24.
//

import Foundation
import GroupActivities
import Combine

class GroupPass {
    typealias ID = UUID
    typealias FromID = GroupActivities.Participant.ID
    typealias Session = String
    
    var id: UUID
    var connectionState: ConnectionState = .disconnected
    var displayName: String { groupParticipant?.description ?? id.uuidString }
    var groupParticipant: GroupActivities.Participant!
    let participant: MultiPass.Participant
    
    required init(_ fromID: FromID, session: String, participant: MultiPass.Participant) {
        self.id = fromID // Since this is also UUID, we just save one ID
        self.participant = participant
    }
}
