//! Re-launches this executable as a detached background process.
use std::ffi::CString;
use std::os::unix::ffi::OsStrExt;
use std::ptr;

/// Not exported by the libc crate for Apple targets.
const POSIX_SPAWN_SETSID: libc::c_short = 0x0400;

/// Spawns the same binary with `arguments` in a new session, with stdin, stdout and stderr
/// pointing at /dev/null, and returns its pid. The child outlives the terminal; the caller
/// either exits right away or `waitpid`s on the returned pid.
pub fn spawn_detached(arguments: &[String]) -> Result<libc::pid_t, String> {
    let exe = std::env::current_exe().map_err(|e| format!("could not determine the executable path: {e}"))?;
    let exe = CString::new(exe.as_os_str().as_bytes()).map_err(|_| "executable path contains NUL".to_string())?;

    let mut argv_owned: Vec<CString> = Vec::with_capacity(arguments.len() + 1);
    argv_owned.push(exe.clone());
    for arg in arguments {
        argv_owned.push(CString::new(arg.as_bytes()).map_err(|_| "argument contains NUL".to_string())?);
    }
    let mut argv: Vec<*mut libc::c_char> = argv_owned.iter().map(|a| a.as_ptr() as *mut _).collect();
    argv.push(ptr::null_mut());

    let env_owned: Vec<CString> = std::env::vars_os()
        .filter_map(|(k, v)| {
            let mut kv = k;
            kv.push("=");
            kv.push(v);
            CString::new(kv.as_bytes()).ok()
        })
        .collect();
    let mut envp: Vec<*mut libc::c_char> = env_owned.iter().map(|e| e.as_ptr() as *mut _).collect();
    envp.push(ptr::null_mut());

    let dev_null = CString::new("/dev/null").unwrap();
    let mut pid: libc::pid_t = 0;
    // SAFETY: plain posix_spawn usage; every pointer handed over outlives the call.
    let status = unsafe {
        let mut attrs: libc::posix_spawnattr_t = std::mem::zeroed();
        libc::posix_spawnattr_init(&mut attrs);
        libc::posix_spawnattr_setflags(&mut attrs, POSIX_SPAWN_SETSID);

        let mut actions: libc::posix_spawn_file_actions_t = std::mem::zeroed();
        libc::posix_spawn_file_actions_init(&mut actions);
        for fd in 0..3 {
            let flags = if fd == 0 { libc::O_RDONLY } else { libc::O_WRONLY };
            libc::posix_spawn_file_actions_addopen(&mut actions, fd, dev_null.as_ptr(), flags, 0);
        }

        let status = libc::posix_spawn(&mut pid, exe.as_ptr(), &actions, &attrs, argv.as_ptr(), envp.as_ptr());
        libc::posix_spawn_file_actions_destroy(&mut actions);
        libc::posix_spawnattr_destroy(&mut attrs);
        status
    };
    if status != 0 {
        return Err(format!(
            "posix_spawn failed: {}",
            std::io::Error::from_raw_os_error(status)
        ));
    }
    Ok(pid)
}

/// Blocks until the child with `pid` has exited.
pub fn wait_for(pid: libc::pid_t) {
    let mut status: libc::c_int = 0;
    // SAFETY: waitpid on a pid we spawned.
    unsafe {
        libc::waitpid(pid, &mut status, 0);
    }
}
