import CryptoKit
import Foundation

struct XFYunAuthSigner: Sendable {
    enum SignerError: Error {
        case invalidEndpoint
    }

    private let endpoint: URL

    init(endpoint: URL = URL(string: "wss://rtasr.xfyun.cn/v1/ws")!) {
        self.endpoint = endpoint
    }

    func signedURL(credentials: XFYunCredentials, timestamp: Int64) throws -> URL {
        let source = Data("\(credentials.appID)\(timestamp)".utf8)
        let digest = Insecure.MD5.hash(data: source)
        let checksum = digest.map { String(format: "%02x", $0) }.joined()
        let key = SymmetricKey(data: Data(credentials.appKey.utf8))
        let signature = HMAC<Insecure.SHA1>.authenticationCode(
            for: Data(checksum.utf8),
            using: key
        )

        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw SignerError.invalidEndpoint
        }
        components.queryItems = [
            URLQueryItem(name: "appid", value: credentials.appID),
            URLQueryItem(name: "ts", value: String(timestamp)),
            URLQueryItem(name: "signa", value: Data(signature).base64EncodedString()),
        ]
        guard let url = components.url else {
            throw SignerError.invalidEndpoint
        }
        return url
    }
}
