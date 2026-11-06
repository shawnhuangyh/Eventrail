import Foundation
import Vision

/// Reads the QR code off a picture of a queue ticket on the device, with
/// Apple's Vision. The picture never leaves the phone and is not kept once
/// read; what stays is the link, once the reader has seen where it goes.
nonisolated enum QueueTicketScanner {
    /// The web pages the QR codes on the picture point at.
    @concurrent static func links(in imageData: Data) async throws -> [URL] {
        var request = DetectBarcodesRequest()
        request.symbologies = [.qr, .microQR]
        let codes = try await request.perform(on: imageData, orientation: TicketScanner.orientation(of: imageData))
        return QueueTicket.links(inCodes: codes.compactMap(\.payloadString))
    }
}
