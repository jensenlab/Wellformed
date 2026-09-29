"""
Posts a line to a Basecamp Campfire via a chatbot URL (Basecamp: Campfire > chatbots). The URL
embeds the credential, so it comes from config/`WELLFORMED_BASECAMP_URL` and is never logged.
Uses `curl` (bundled with Windows 10+ and macOS) to avoid an HTTP dependency in the built app.
"""
struct BasecampNotifier <: Notifier
    url::String
end

function notify(n::BasecampNotifier, r::CheckResult, cfg::Config)
    isempty(n.url) && error("basecamp enabled but no chatbot url configured")
    body = alert_text(r, cfg)
    run(`curl --silent --show-error --fail --max-time 20 --data-urlencode $("content=" * body) $(n.url)`)
    return nothing
end
