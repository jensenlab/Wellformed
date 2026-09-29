@enum Status OK WARN FAIL

struct Issue
    severity::Status
    message::String
end

struct CheckResult
    path::String
    status::Status
    issues::Vector{Issue}
    summary::String
    seconds::Float64
end

_worst(issues) = isempty(issues) ? OK : maximum(i.severity for i in issues)

# A truncated .xlsx is a zip missing its tail: the End Of Central Directory record (PK\x05\x06) is
# written last, so its absence in the final 64 KiB + 22 bytes is the classic truncation signature.
function _zip_has_eocd(path::AbstractString)
    sz = filesize(path)
    sz < 22 && return false
    n = min(sz, 22 + 65535)
    tail = open(path) do io
        seek(io, sz - n)
        read(io, n)
    end
    sig = UInt8[0x50, 0x4b, 0x05, 0x06]
    for i in length(tail)-3:-1:1
        @views tail[i:i+3] == sig && return true
    end
    return false
end

_errmsg(e) = first(split(sprint(showerror, e), '\n'))

# "A1" -> ('A', 1); "AA12" -> ("AA", 12)
function _split_well(w::AbstractString)
    m = match(r"^([A-Za-z]+)(\d+)$", strip(w))
    m === nothing && return nothing
    return (uppercase(m[1]), parse(Int, m[2]))
end

function _sanity!(issues::Vector{Issue}, r::CHESSParsers.LabwareRead)
    plate = get(r.metadata, "plate", "?")
    kind = get(r.metadata, "read_kind", "?")
    tag = "plate $plate ($kind)"
    df = r.data
    if nrow(df) == 0
        push!(issues, Issue(FAIL, "$tag: no data rows"))
        return
    end
    n_bad = count(v -> ismissing(v) || (v isa AbstractFloat && !isfinite(v)), df.value)
    n_bad > 0 && push!(issues, Issue(WARN, "$tag: $n_bad of $(nrow(df)) values are missing/non-finite"))

    # Timepoints per well must agree; a table cut off mid-row leaves later wells short.
    counts = combine(groupby(df, :well), nrow => :n)
    if length(unique(counts.n)) > 1
        common = argmax(c -> count(==(c), counts.n), unique(counts.n))
        short = counts.well[counts.n .!= common]
        shown = join(first(short, 6), ", ") * (length(short) > 6 ? ", ..." : "")
        push!(issues, Issue(FAIL, "$tag: wells have inconsistent numbers of readings " *
                                  "(most have $common; differing: $shown)"))
    end

    # Wells should form a complete rectangle (partial plates are fine, ragged ones are not).
    parsed = filter(!isnothing, _split_well.(String.(unique(df.well))))
    if !isempty(parsed)
        rows = unique(first.(parsed)); cols = unique(last.(parsed))
        if length(parsed) != length(rows) * length(cols)
            push!(issues, Issue(WARN, "$tag: $(length(parsed)) wells do not form a complete " *
                                      "$(length(rows))x$(length(cols)) block"))
        end
    end
end

function _sanity!(issues::Vector{Issue}, r::CHESSParsers.EnvironmentLog)
    kind = get(r.metadata, "read_kind", "?")
    nrow(r.data) == 0 && push!(issues, Issue(FAIL, "environment log $kind: no data rows"))
end

_sanity!(issues::Vector{Issue}, r) = nothing

"""
    check_file(path; unrecognized_is_failure=true) -> CheckResult

Decide whether the instrument export at `path` is well-formed: it must survive a
`CHESSParsers.parse_instrument_file` parse and pass a few structural sanity checks.
"""
function check_file(path::AbstractString; unrecognized_is_failure::Bool=true)
    t0 = time()
    issues = Issue[]
    summary = ""
    finish() = CheckResult(String(path), _worst(issues), issues, summary, time() - t0)

    if !isfile(path)
        push!(issues, Issue(FAIL, "file not found"))
        return finish()
    end
    if filesize(path) == 0
        push!(issues, Issue(FAIL, "file is empty (0 bytes)"))
        return finish()
    end
    if endswith(lowercase(path), ".xlsx") && !_zip_has_eocd(path)
        push!(issues, Issue(FAIL, "xlsx is truncated: zip end-of-file record is missing"))
        return finish()
    end

    fmt = try
        CHESSParsers.detect_format(path)
    catch e
        push!(issues, Issue(FAIL, "could not read file: " * _errmsg(e)))
        return finish()
    end
    if fmt === nothing
        push!(issues, Issue(unrecognized_is_failure ? FAIL : WARN,
                            "not recognized as any known instrument export format"))
        return finish()
    end

    results = try
        CHESSParsers.parse_raw(fmt, path)
    catch e
        why = endswith(lowercase(path), ".xlsx") ? _xlsx_diagnosis(path) : nothing
        msg = "parse failed ($(nameof(fmt))): " * _errmsg(e)
        why === nothing || (msg = why * " [" * msg * "]")
        push!(issues, Issue(FAIL, msg))
        return finish()
    end
    if isempty(results)
        push!(issues, Issue(FAIL, "parsed as $(nameof(fmt)) but contained no reads"))
        return finish()
    end
    for r in results
        _sanity!(issues, r)
    end
    nwells = sum(r -> r isa CHESSParsers.LabwareRead ? length(unique(r.data.well)) : 0, results)
    summary = "$(nameof(fmt)): $(length(results)) read(s)" * (nwells > 0 ? ", $nwells well(s)" : "")
    return finish()
end

# When a parse of an .xlsx fails, look at the sheet itself to say *why* in plain words. Returns
# nothing if the sheet looks structurally complete (then the raw parser error is all we have).
# A Gen5 export is a metadata header (2 columns) followed by data tables (many columns); a sheet
# that never widens past the header was cut off before any plate data was written.
function _xlsx_diagnosis(path::AbstractString)
    try
        xf = XLSX.readxlsx(path)
        for name in XLSX.sheetnames(xf)
            M = xf[name][:]
            M isa AbstractMatrix || continue
            nrows, ncols = size(M)
            filled = [count(!ismissing, @view M[i, :]) for i in 1:nrows]
            if !any(>=(3), filled)
                last = findlast(i -> !ismissing(M[i, 1]) || (ncols > 1 && !ismissing(M[i, 2])), 1:nrows)
                where_ = last === nothing ? "" : " (last line: \"" *
                    first(join(skipmissing(M[last, 1:min(2, ncols)]), " "), 60) * "\")"
                return "sheet \"$name\" has a header but no data table$where_; the export was likely cut off"
            end
        end
    catch
    end
    return nothing
end
