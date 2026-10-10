import Foundation

/// Refuse to run an app version older than the newest one this Mac has already run (no downgrade
/// to a signed build with a known bug). Versions are CFBundleVersion integers.
public enum VersionFloor {
    public static func allows(_ version: String, floor: String?) -> Bool {
        guard let current = Int(version) else { return false }
        guard let floor, let minimum = Int(floor) else { return true }
        return current >= minimum
    }
}

/// The helper keeps its state only in a folder that is a real directory owned by root and not
/// writable by anyone else (admin users can write /Library/Application Support).
public enum SafeFolder {
    public static func isRootOwnedRealFolder(_ path: String) -> Bool {
        var info = stat()
        guard lstat(path, &info) == 0 else { return false }
        let isDirectory = (info.st_mode & S_IFMT) == S_IFDIR
        let othersCanWrite = (info.st_mode & (S_IWGRP | S_IWOTH)) != 0
        return isDirectory && info.st_uid == 0 && !othersCanWrite
    }
}
