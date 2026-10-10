import Foundation
import Security

/// The root helper only uses an app bundle whose complete signature checks out: executables, the
/// bundled sing-box (nested code) and every sealed resource, including the user's settings and the lists.
public enum AppBundleTrust {
    public static let requirement = HelperConstants.developerIDRequirement(identifier: HelperConstants.appBundleID)

    public static func isSignedByUs(bundle: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess, let code else { return false }
        var req: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidity(code, flags, req) == errSecSuccess
    }
}
