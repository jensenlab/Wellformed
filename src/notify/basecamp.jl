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

function notify(n::BasecampNotifier, r::CheckResult, cfg::Config)
    isempty(n.url) && error("basecamp enabled but no chatbot url configured")
    # Basecamp shows the chatbot address ending in /line, but lines are posted to /lines.
    url = replace(rstrip(n.url, '/'), r"/line$" => "/lines")
    body = alert_text(r, cfg)
    run(`$(_curl()) --silent --show-error --fail --max-time 20 --data-urlencode $("content=" * body) $url`)
    return nothing
end
