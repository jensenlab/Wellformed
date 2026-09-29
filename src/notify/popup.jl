"Blocking always-on-top dialog. `notify` returns only after the operator dismisses it."
struct PopupNotifier <: Notifier end

function notify(::PopupNotifier, r::CheckResult, cfg::Config)
    title = r.status == FAIL ? "Wellformed: BAD DATA FILE" : "Wellformed: warning"
    msg = alert_text(r, cfg)
    # Text goes through the environment so no quoting/escaping of file names is needed.
    env = ["WF_TITLE" => title, "WF_MSG" => msg]
    cmd = if Sys.iswindows()
        ps = "Add-Type -AssemblyName System.Windows.Forms; " *
             "\$f = New-Object System.Windows.Forms.Form -Property @{TopMost=\$true}; " *
             "[void][System.Windows.Forms.MessageBox]::Show(\$f, \$env:WF_MSG, \$env:WF_TITLE, 'OK', 'Warning')"
        `powershell -NoProfile -NonInteractive -Command $ps`
    elseif Sys.isapple()
        script = "display alert (system attribute \"WF_TITLE\") message (system attribute \"WF_MSG\") as critical"
        `osascript -e $script`
    else
        `zenity --warning --title=$title --text=$msg`
    end
    run(addenv(cmd, env...))
    return nothing
end
