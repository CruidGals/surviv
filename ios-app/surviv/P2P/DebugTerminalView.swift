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
    @State private var messageInput = ""
    @State private var secretInput = ""
    @State private var showSecretField = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // SECTION 1: Peer Status
                HStack {
                    VStack(alignment: .leading) {
                        Text("DEVICE ROLE")
                            .font(.caption2).foregroundColor(.gray)
                        Text(networker.userRole.rawValue)
                            .font(.headline)
                            .foregroundColor(networker.userRole == .admin ? .red : .blue)
                    }
                    Spacer()
                    Text("\(networker.connectedPeers.count) Peers Online")
                        .font(.caption).padding(6)
                        .background(Capsule().stroke(Color.gray))
                }
                .padding()
                .background(Color(.secondarySystemBackground))

                // SECTION 2: Message Log
                List(networker.incomingMessages.reversed(), id: \.id) { packet in
                    VStack(alignment: .leading) {
                        Text(packet.senderName).font(.caption).bold()
                        Text(packet.message)
                        Text(packet.timestamp, style: .time)
                            .font(.system(size: 8, design: .monospaced))
                    }
                    .listRowSeparator(.hidden)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)))
                }
                .listStyle(.plain)

                // SECTION 3: Input
                VStack(spacing: 12) {
                    if networker.userRole == .scout {
                        if showSecretField {
                            HStack {
                                SecureField("Enter Secret...", text: $secretInput)
                                    .textFieldStyle(.roundedBorder)
                                Button("Confirm") {
                                    networker.promoteToAdmin(secret: secretInput)
                                    showSecretField = false
                                }
                            }
                        } else {
                            Button("REQUEST ADMIN PROMOTION") {
                                showSecretField = true
                            }
                            .font(.caption).bold()
                        }
                    } else {
                        // ADMIN BROADCASTING
                        HStack {
                            TextField("Broadcast Message...", text: $messageInput)
                                .textFieldStyle(.roundedBorder)
                            Button("SEND") {
                                networker.broadcast(message: messageInput)
                                messageInput = ""
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
            }
            .navigationTitle("Surviv Node")
        }
    }
}
