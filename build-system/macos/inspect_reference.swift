import Foundation
import Security
import CommonCrypto

let url = URL(fileURLWithPath: CommandLine.arguments[1])
var rawCode: SecStaticCode?
guard SecStaticCodeCreateWithPath(url as CFURL, [], &rawCode) == errSecSuccess, let code = rawCode else { fatalError("Cannot inspect static code") }
var rawInfo: CFDictionary?
guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &rawInfo) == errSecSuccess, let info = rawInfo as? [String: Any], let rawTrust = info[kSecCodeInfoTrust as String] else { fatalError("Missing signing trust") }
let trust = rawTrust as! SecTrust
var certificateData = Data()
var subjects: [String] = []
for index in 0..<SecTrustGetCertificateCount(trust) {
    guard let certificate = SecTrustGetCertificateAtIndex(trust, index) else { fatalError("Missing chain certificate") }
    certificateData.append(SecCertificateCopyData(certificate) as Data)
    subjects.append(SecCertificateCopySubjectSummary(certificate) as String? ?? "")
}
var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
certificateData.withUnsafeBytes { _ = CC_SHA1($0.baseAddress, CC_LONG($0.count), &digest) }
let metadata = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any] ?? [:]
let result: [String: Any] = ["signing_certificate_sha1": digest.map { String(format: "%02x", $0) }.joined(), "certificate_subjects": subjects, "bundle_id": metadata["CFBundleIdentifier"] ?? "", "version": metadata["CFBundleShortVersionString"] ?? "", "build": metadata["CFBundleVersion"] ?? "", "source": metadata["SOURCE"] ?? ""]
let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
print(String(data: data, encoding: .utf8)!)
