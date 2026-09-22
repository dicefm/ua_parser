# EXPERIMENTAL - compares UAParser.Experimental.TreeMatcher (a compile-time
# generated recursive matcher, no Regex at all) against the existing
# UAParser.Index + Regex.run path, for just the user-agent identification
# step (family + version), on the small set of high-volume, regular
# templates the tree document covers (Chrome-family, Firefox, Safari).
#
# This isolates "cost of identifying the browser" on both sides - it does
# NOT run OS/device parsing, since TreeMatcher only attempts the user-agent
# question. See UAParser.Experimental.TreeMatcher's moduledoc for why this
# comparison exists.
#
#     mix run bench/tree_vs_regex.exs

alias UAParser.Experimental.TreeMatcher
alias UAParser.Index

{ua_index, _os_index, _device_index} = UAParser.Storage.indexes()

# Real UAs from production traffic (the same shapes discussed in this
# session), plus a couple of extra branches (Opera, Samsung Internet) the
# original sample didn't include, to exercise every branch in the tree.
uas = [
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15",
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:128.0) Gecko/20100101 Firefox/128.0",
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0",
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 OPR/110.0.0.0",
  "Mozilla/5.0 (Linux; Android 13; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/23.0 Chrome/115.0.0.0 Mobile Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
]

# --- correctness: does TreeMatcher agree with UAParser.parse/1? ---

IO.puts("=== correctness ===\n")

Enum.each(uas, fn ua ->
  real = UAParser.parse(ua)
  real_family = real.family
  real_version = to_string(real.version)

  case TreeMatcher.match(ua) do
    :no_match ->
      IO.puts("no_match  (real: #{inspect(real_family)} #{inspect(real_version)})  #{String.slice(ua, 0, 50)}")

    {family, version} ->
      status = if family == real_family, do: "OK", else: "FAMILY MISMATCH"
      IO.puts("#{status}  tree: #{family} #{version}  real: #{real_family} #{real_version}  #{String.slice(ua, 0, 40)}")
  end
end)

# --- speed: index+regex vs tree, on the covered UAs only ---

covered = Enum.filter(uas, &(TreeMatcher.match(&1) != :no_match))

IO.puts("\n=== speed (#{length(covered)} of #{length(uas)} UAs the tree covers, one pass per iteration) ===\n")

find_via_index = fn ua ->
  case Index.find(ua_index, ua) do
    nil -> nil
    {group, match} -> UAParser.Parsers.UA.parse({group, match})
  end
end

Benchee.run(
  %{
    "Index + Regex.run" => fn -> Enum.each(covered, find_via_index) end,
    "TreeMatcher" => fn -> Enum.each(covered, &TreeMatcher.match/1) end
  },
  time: 8,
  warmup: 2,
  memory_time: 2
)

# --- the catch: modern crawlers spoof these exact shapes ---
#
# Googlebot and Bingbot's current UA strings embed real "Chrome/" and
# "Safari/" tokens for site-compatibility reasons - the same tokens this
# tree's Chrome branch keys off, with no awareness that a "Googlebot"/
# "Bingbot" marker elsewhere in the string should take priority. The
# general Index + patterns.yml gets this right because bot patterns are
# part of the same ordered list; this narrow tree does not know they
# exist at all.

IO.puts("\n=== the catch: bot UAs that spoof these exact shapes ===\n")

spoofing_uas = [
  {"Mozilla/5.0 (Linux; Android 6.0.1; Nexus 5X Build/MMB29P) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/W.X.Y.Z Mobile Safari/537.36 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
   "Googlebot"},
  {"Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; Bingbot/2.0; +http://www.bing.com/bingbot.htm) Chrome/116.0.5845.96 Safari/537.36",
   "bingbot"}
]

Enum.each(spoofing_uas, fn {ua, expected_family} ->
  real = UAParser.parse(ua)
  tree = TreeMatcher.match(ua)
  IO.puts("real: #{inspect(real.family)} (expected #{inspect(expected_family)})   tree (WRONG): #{inspect(tree)}")
end)

IO.puts("""

A cheap guard ("bail to :no_match if the string contains bot/crawler/spider")
patches these two specific cases without breaking the good ones - but that is
reactive, one exclusion at a time, against a pattern list this tree has no
visibility into. Every such guard re-derives, by hand, a piece of the
ordering/priority logic patterns.yml's full pattern list already encodes.
There is no guarantee this is the only spoofing shape out there; it is only
the one this session happened to think to test.
""")
