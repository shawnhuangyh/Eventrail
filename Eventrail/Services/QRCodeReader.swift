import Foundation
import Vision

/// Reads the QR codes off a picture on the device, with Apple's Vision: a queue
/// ticket's or a set list's. The picture never leaves the phone and is not kept
/// once read; what stays is the link, once the reader has seen where it goes.
nonisolated enum QRCodeReader {
    /// The web pages the QR codes on the picture point at.
    @concurrent static func links(in imageData: Data) async throws -> [URL] {
        var request = DetectBarcodesRequest()
        request.symbologies = [.qr, .microQR]
        let codes = try await request.perform(on: imageData, orientation: TicketScanner.orientation(of: imageData))
        return QRCodeLink.links(inCodes: codes.compactMap(\.payloadString))
    }
}
