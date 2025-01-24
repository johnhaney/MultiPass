//
//  MultiConnector.swift
//  MultiPass
//
//  Created by John Haney on 7/13/24.
//

import Foundation

protocol MultiConnector {
    var id: UUID { get }
    var multipass: MultiPass { get set }

    func send(data: Data, reliable: Bool)
    
    func start()
    func stop()
}
