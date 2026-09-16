    // Laid into unmodified upstream by forks/herdr/prove, inside the tests module of
    // src/detect/mod.rs, to ask one question. Does vanilla upstream now identify an agent that
    // sits behind a pty proxy. It uses only what vanilla has, the foreground job and the
    // identification, and never the walk this fork adds, so it compiles there and fails there.
    //
    // Passing means upstream has taken a fix of its own and the branch can go. It can answer
    // wrongly in one direction only. An upstream that fixes this somewhere other than inside
    // foreground_job, in a fallback of its own, would leave this failing and the patch carried
    // one cycle longer than needed, which the release notes the reporter prints would catch.
    #[cfg(any(target_os = "linux", target_os = "macos"))]
    #[test]
    fn mdj_probe_upstream_identifies_agent_behind_pty_proxy() {
        use portable_pty::CommandBuilder;

        let pair = portable_pty::native_pty_system()
            .openpty(portable_pty::PtySize {
                rows: 24,
                cols: 80,
                pixel_width: 0,
                pixel_height: 0,
            })
            .expect("failed to open pty");

        let mut cmd = CommandBuilder::new("script");
        #[cfg(target_os = "macos")]
        {
            cmd.arg("-q");
            cmd.arg("/dev/null");
            cmd.arg("bash");
            cmd.arg("-c");
            cmd.arg("exec -a claude sleep 999");
        }
        #[cfg(target_os = "linux")]
        {
            cmd.arg("-q");
            cmd.arg("-c");
            cmd.arg("bash -c 'exec -a claude sleep 999'");
            cmd.arg("/dev/null");
        }

        let mut child = pair.slave.spawn_command(cmd).expect("failed to spawn");
        let pid = child.process_id().expect("no pid");
        std::thread::sleep(std::time::Duration::from_millis(500));

        let job = foreground_job(pid);
        let identified = job.as_ref().and_then(identify_agent_in_job);

        let group = job.as_ref().map(|job| job.process_group_id).unwrap_or(pid);
        unsafe {
            libc::kill(-(group as i32), libc::SIGKILL);
        }
        child.wait().ok();

        assert!(
            identified.is_some(),
            "vanilla upstream still cannot see an agent behind a pty proxy, the patch is needed"
        );
    }
