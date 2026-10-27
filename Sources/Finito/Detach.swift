import Darwin
import Foundation

/// Re-launches this executable as a detached background process and returns its pid.
///
/// `fork()` is not an option once AppKit/CoreFoundation are loaded, so we `posix_spawn` the same
/// binary in a new session with stdin/stdout/stderr pointing at /dev/null. The child outlives the
/// terminal; the caller either exits right away or `waitpid`s on the returned pid.
func spawnDetached(arguments: [String]) throws -> pid_t {
    var size: UInt32 = 0
    _ = _NSGetExecutablePath(nil, &size)
    var buffer = [CChar](repeating: 0, count: Int(size))
    guard _NSGetExecutablePath(&buffer, &size) == 0 else {
        throw DetachError.executablePath
    }
    let executable = String(cString: buffer)

    var attrs: posix_spawnattr_t?
    posix_spawnattr_init(&attrs)
    defer { posix_spawnattr_destroy(&attrs) }
    posix_spawnattr_setflags(&attrs, Int16(POSIX_SPAWN_SETSID))

    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    for fd: Int32 in 0...2 {
        posix_spawn_file_actions_addopen(&actions, fd, "/dev/null", fd == 0 ? O_RDONLY : O_WRONLY, 0)
    }

    let argv = [executable] + arguments
    var cArgv: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) } + [nil]
    defer { cArgv.forEach { free($0) } }

    var pid: pid_t = 0
    let status = posix_spawn(&pid, executable, &actions, &attrs, &cArgv, environ)
    guard status == 0 else { throw DetachError.spawn(status) }
    return pid
}

enum DetachError: Error, CustomStringConvertible {
    case executablePath
    case spawn(Int32)

    var description: String {
        switch self {
        case .executablePath: return "could not determine the executable path"
        case .spawn(let code): return "posix_spawn failed: \(String(cString: strerror(code)))"
        }
    }
}
