// Ed25519 checks for scripts/generate-appcast.sh, with CryptoKit (no third-party code):
//
//   sparkle-ed25519 public-key              < private-key   → the SUPublicEDKey for that key
//   sparkle-ed25519 verify <public> <signature> <file>      → exit 0 when the signature is valid
//
// The private key is Sparkle's exported format (`generate_keys -x`): base64 of the 32-byte seed,
// read from standard input only, so it never appears in a process list or a file.
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("sparkle-ed25519: \(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments.dropFirst()
switch arguments.first {
case "public-key":
    let input = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let seed = Data(base64Encoded: input), seed.count == 32 else {
        fail("the private key must be base64 of a 32-byte Ed25519 seed (Sparkle's generate_keys -x format)")
    }
    guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) else { fail("invalid private key") }
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "verify" where arguments.count == 4:
    let values = Array(arguments)
    guard let publicData = Data(base64Encoded: values[1]), publicData.count == 32,
          let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicData) else {
        fail("the public key must be base64 of 32 bytes")
    }
    guard let signature = Data(base64Encoded: values[2]), signature.count == 64 else {
        fail("the signature must be base64 of 64 bytes")
    }
    guard let file = try? Data(contentsOf: URL(fileURLWithPath: values[3]), options: .alwaysMapped) else {
        fail("cannot read \(values[3])")
    }
    guard publicKey.isValidSignature(signature, for: file) else { fail("signature does not match \(values[3])") }
    print("EdDSA signature verified")
default:
    fail("usage: sparkle-ed25519 public-key < key | sparkle-ed25519 verify <public-key> <signature> <file>")
}
