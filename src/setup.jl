# First-run / --setup flow: pick the folder to watch, paste the Basecamp chatbot URL, save the
# config, send a test alert. Prompts go through native dialogs on Windows/macOS (text is passed in
# environment variables, so no quoting issues) and plain terminal prompts elsewhere. All prompts
# live in a `UI` so tests can script them.

Base.@kwdef struct UI
    folder::Function   # (prompt, default) -> Union{String,Nothing}   (nothing = cancelled)
    text::Function     # (prompt, default) -> Union{String,Nothing}
    yesno::Function    # (prompt)          -> Bool
    say::Function      # (msg)             -> nothing
end

const _TITLE = "Wellformed setup"

# Run a dialog command; its stdout is the answer. Cancel/failure -> nothing.
function _dialog(cmd::Cmd, prompt, default="")
    try
        out = read(pipeline(addenv(cmd, "WF_PROMPT" => prompt, "WF_DEFAULT" => default, "WF_TITLE" => _TITLE);
                            stderr=devnull), String)
        s = strip(out)
        return isempty(s) ? nothing : String(s)
    catch
        return nothing
    end
end

const _PS_HEAD = "Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName Microsoft.VisualBasic; " *
                 "\$f = New-Object System.Windows.Forms.Form -Property @{TopMost=\$true}; "
_ps(body) = `powershell -NoProfile -NonInteractive -STA -Command $(_PS_HEAD * body)`

function _win_ui()
    UI(
        folder = (p, d) -> _dialog(_ps("\$d = New-Object System.Windows.Forms.FolderBrowserDialog; " *
                                       "\$d.Description = \$env:WF_PROMPT; \$d.SelectedPath = \$env:WF_DEFAULT; " *
                                       "if (\$d.ShowDialog(\$f) -eq 'OK') { [Console]::Out.Write(\$d.SelectedPath) }"), p, d),
        text = (p, d) -> _dialog(_ps("[Console]::Out.Write([Microsoft.VisualBasic.Interaction]::InputBox(" *
                                     "\$env:WF_PROMPT, \$env:WF_TITLE, \$env:WF_DEFAULT))"), p, d),
        yesno = p -> _dialog(_ps("[Console]::Out.Write([System.Windows.Forms.MessageBox]::Show(\$f, \$env:WF_PROMPT, " *
                                 "\$env:WF_TITLE, 'YesNo', 'Question'))"), p) == "Yes",
        say = println,
    )
end

function _mac_ui()
    osa(script) = `osascript -e $script`
    UI(
        folder = (p, d) -> _dialog(osa("POSIX path of (choose folder with prompt (system attribute \"WF_PROMPT\"))"), p, d),
        text = (p, d) -> _dialog(osa("text returned of (display dialog (system attribute \"WF_PROMPT\") " *
                                     "default answer (system attribute \"WF_DEFAULT\") with title (system attribute \"WF_TITLE\"))"), p, d),
        yesno = p -> _dialog(osa("button returned of (display dialog (system attribute \"WF_PROMPT\") " *
                                 "buttons {\"No\", \"Yes\"} default button \"Yes\" with title (system attribute \"WF_TITLE\"))"), p) == "Yes",
        say = println,
    )
end

function _terminal_ui()
    ask(p, d) = begin
        print(p, isempty(d) ? "" : " [$d]", ": ")
        s = strip(something(readline(stdin), ""))
        isempty(s) ? (isempty(d) ? nothing : String(d)) : String(s)
    end
    UI(folder = ask, text = ask,
       yesno = p -> (a = ask(p * " (y/n)", ""); a !== nothing && lowercase(first(a)) == 'y'),
       say = println)
end

default_ui() = Sys.iswindows() ? _win_ui() : Sys.isapple() ? _mac_ui() : _terminal_ui()

const _BC_URL_RE = r"^https://[\w.-]*basecamp\.com/\d+/integrations/[^/\s]+/buckets/\d+/chats/\d+/lines?/?$"

"""
    run_setup(path=config_path(); ui=default_ui(), test_alert=true, offer_startup=true) -> Union{Config,Nothing}

Interactive configuration. Existing values in `path` become the defaults, so re-running it is a
safe way to change the folder or URL. Returns the saved [`Config`](@ref), or `nothing` if the
user cancelled.
"""
function run_setup(path::AbstractString=config_path(); ui::UI=default_ui(), test_alert::Bool=true,
                   offer_startup::Bool=true)
    old = isfile(path) ? load_config(path) : Config()
    dir = ui.folder("Choose the folder your plate reader exports data files to.",
                    isempty(old.watch_dirs) ? homedir() : first(old.watch_dirs))
    if dir === nothing
        ui.say("Setup cancelled; nothing was saved.")
        return nothing
    end
    dir = abspath(dir)
    if !isdir(dir)
        ui.say("That folder does not exist: $dir. Nothing was saved.")
        return nothing
    end

    url = ""
    prompt = "Paste the Basecamp Campfire chatbot URL to post alerts to.\nLeave blank for popup alerts only."
    default = old.basecamp_url
    for _ in 1:3
        ans = ui.text(prompt, default)
        ans === nothing && break
        ans = strip(ans)
        if isempty(ans) || occursin(_BC_URL_RE, ans)
            url = String(ans); break
        end
        prompt = "That doesn't look like a Basecamp chatbot URL (expected\nhttps://3.basecamp.com/<account>/integrations/<key>/buckets/<n>/chats/<n>/lines).\nPaste it again, or leave blank to skip."
        default = ""
    end

    cfg = with(old; watch_dirs=[dir], basecamp_enabled=!isempty(url), basecamp_url=url,
               log_path=joinpath(dirname(abspath(path)), "wellformed.log"))
    save_config(cfg, path)
    ui.say("Saved settings to $path")

    if test_alert
        r = CheckResult("TEST_ALERT.xlsx", FAIL,
                        [Issue(FAIL, "This is a test of the Wellformed alert. No real file is affected.")], "", 0.0)
        # Basecamp first: its result is reported here, then the popup (which blocks until clicked).
        for n in default_notifiers(cfg)
            n isa PopupNotifier && continue
            try
                notify(n, r, cfg); ui.say("Test post sent to Basecamp - check the Campfire.")
            catch e
                ui.say("Could not post to Basecamp: " * _errmsg(e))
            end
        end
        cfg.popup_enabled && (try notify(PopupNotifier(), r, cfg) catch e
            ui.say("Could not show a popup: " * _errmsg(e)) end)
    end

    if offer_startup && ui.yesno("Start Wellformed automatically when you log in?")
        try
            install_startup()
            ui.say("Wellformed will start when you log in.")
        catch e
            ui.say("Could not set up start at login: " * _errmsg(e))
        end
    end
    return cfg
end
