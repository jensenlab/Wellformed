"""
Posts a line to a Basecamp Campfire via a chatbot URL (Basecamp: Campfire > chatbots). The URL
embeds the credential, so it comes from config/`WELLFORMED_BASECAMP_URL` and is never logged.
Uses `curl` (bundled with Windows 10+ and macOS) to avoid an HTTP dependency in the built app.
"""
struct BasecampNotifier <: Notifier
    url::String
end

# Use the OS-provided curl on macOS: a stray curl earlier on PATH (e.g. a wrong-architecture
# Anaconda build) would otherwise fail with "Bad CPU type". Windows 10+ ships curl.exe on PATH.
_curl() = Sys.isapple() && isfile("/usr/bin/curl") ? "/usr/bin/curl" : "curl"

# Basecamp shows the chatbot address ending in /line, but lines are posted to /lines.
_lines_url(u::AbstractString) = replace(rstrip(strip(u), '/'), r"/line$" => "/lines")

function notify(n::BasecampNotifier, r::CheckResult, cfg::Config)
    isempty(n.url) && error("basecamp enabled but no chatbot url configured")
    url = _lines_url(n.url)
    body = alert_text(r, cfg)
    err = IOBuffer()
    cmd = `$(_curl()) --silent --show-error --fail --max-time 20 --data-urlencode $("content=" * body) $url`
    ok = try
        success(pipeline(cmd; stderr=err))
    catch e   # e.g. curl missing; the exception text would contain the command line, i.e. the URL
        error("could not run curl: " * replace(_errmsg(e), url => "<url>"))
    end
    ok || error("Basecamp post failed: " * replace(strip(String(take!(err))), url => "<url>"))
    return nothing
end
