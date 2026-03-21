//
//  DebugTerminalView.swift
//  surviv
//
//  Created by Kyle Chiem on 3/21/26.
//

import SwiftUI
import MultipeerConnectivity

struct DebugTerminalView: View {
    @StateObject var networker = SurvivNetworker()
    @State private var textToSend = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // SECTION 1: Peer Status
                VStack(alignment: .leading) {
                    Text("ACTIVE PEERS: \(networker.connectedPeers.count)")
                        .font(.caption).bold()
                    
                    ForEach(networker.connectedPeers, id: \.self) { peer in
                        Label(peer.displayName, systemImage: "iphone.radiowaves.left.and.right")
                            .foregroundColor(.green)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.1))

                // SECTION 2: Message Log
                List(networker.incomingMessages.reversed(), id: \.id) { packet in
                    VStack(alignment: .leading) {
                        Text(packet.senderName).font(.caption).bold()
                        Text(packet.message)
                        Text(packet.timestamp, style: .time)
                            .font(.system(size: 8, design: .monospaced))
                    }
                }

                // SECTION 3: Input
                HStack {
                    TextField("Enter test message...", text: $textToSend)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("Broadcast") {
                        networker.broadcast(message: textToSend)
                        textToSend = ""
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle("Surviv Debug")
        }
    }
}
