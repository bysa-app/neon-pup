import Foundation
import Security

/// The root helper runs the bundled sing-box only if it still carries Holinic's Developer ID
/// signature (security review 2026-10-09): a swapped binary inside a user-writable app folder
/// must not get root.
public enum CodeSignature {
    public static let engineRequirement = HelperConstants.developerIDRequirement(identifier: "sing-box")

    public static func isSignedByUs(path: String, requirement: String = engineRequirement) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess,
              let code else { return false }
        var req: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate)
        return SecStaticCodeCheckValidity(code, flags, req) == errSecSuccess
    }
}
