# Start-at-login without admin rights: a Startup-folder shortcut on Windows, a LaunchAgent on macOS.

const _AGENT_LABEL = "com.jensenlab.wellformed"

"Path of the running app. Only meaningful for a built app, not `julia` itself."
function _app_exe()
    # A PackageCompiler app keeps its launcher next to the bundled runtime: <app>/bin/Wellformed[.exe].
    # (Base.julia_cmd() would point at the helper bin/julia instead.) Under plain Julia this file
    # does not exist, which is what stops us registering `julia` itself as a login item.
    exe = joinpath(Sys.BINDIR, "Wellformed" * (Sys.iswindows() ? ".exe" : ""))
    isfile(exe) || error("start at login only works from the built wellformed app (this is running under Julia); " *
                         "set WELLFORMED_EXE to the app's path to override")
    return exe
end
_exe() = (e = get(ENV, "WELLFORMED_EXE", ""); isempty(e) ? _app_exe() : e)

_windows_shortcut() = joinpath(get(ENV, "APPDATA", homedir()), "Microsoft", "Windows",
                               "Start Menu", "Programs", "Startup", "Wellformed.lnk")
_mac_plist(dir=joinpath(homedir(), "Library", "LaunchAgents")) = joinpath(dir, _AGENT_LABEL * ".plist")

_xml(s) = replace(String(s), "&" => "&amp;", "<" => "&lt;", ">" => "&gt;")

function _plist_text(exe, logdir)
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
      <key>Label</key><string>$(_AGENT_LABEL)</string>
      <key>ProgramArguments</key><array><string>$(_xml(exe))</string></array>
      <key>RunAtLoad</key><true/>
      <key>KeepAlive</key><true/>
      <key>StandardErrorPath</key><string>$(_xml(joinpath(logdir, "stderr.log")))</string>
    </dict></plist>
    """
end

"""
    install_startup(; exe=_exe(), plist_dir=nothing) -> path

Make Wellformed start when the user logs in (Windows: Startup-folder shortcut, started minimized;
macOS: LaunchAgent that also restarts it if it crashes). Safe to call repeatedly.
"""
function install_startup(; exe::AbstractString=_exe(), plist_dir=nothing)
    if Sys.iswindows()
        lnk = _windows_shortcut()
        mkpath(dirname(lnk))
        script = "\$s = (New-Object -ComObject WScript.Shell).CreateShortcut(\$env:WF_LNK); " *
                 "\$s.TargetPath = \$env:WF_EXE; \$s.WorkingDirectory = Split-Path \$env:WF_EXE; " *
                 "\$s.WindowStyle = 7; \$s.Description = 'Wellformed'; \$s.Save()"
        run(addenv(`powershell -NoProfile -NonInteractive -Command $script`, "WF_LNK" => lnk, "WF_EXE" => exe))
        return lnk
    elseif Sys.isapple()
        p = plist_dir === nothing ? _mac_plist() : _mac_plist(plist_dir)
        mkpath(dirname(p))
        write(p, _plist_text(exe, dirname(config_path())))
        return p
    end
    error("start at login is only implemented for Windows and macOS")
end

"Undo [`install_startup`](@ref). Returns whether anything was removed."
function uninstall_startup(; plist_dir=nothing)
    p = Sys.iswindows() ? _windows_shortcut() :
        Sys.isapple() ? (plist_dir === nothing ? _mac_plist() : _mac_plist(plist_dir)) :
        error("start at login is only implemented for Windows and macOS")
    isfile(p) || return false
    rm(p)
    return true
end
