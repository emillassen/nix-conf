"""Collect episode links from a DRTV (dr.dk/drtv) series or season page.

Given a series or season URL, writes every episode URL on its own line,
ready to feed to yt-dlp with `yt-dlp -a links.txt`.

Primary data source is the JSON API behind the DRTV web player (the same
one yt-dlp's DRTV extractor uses). If the API shape ever changes, the
script falls back to scraping episode hrefs out of the page HTML.
"""
import argparse
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

BASE = "https://www.dr.dk/drtv"
PAGE_API = (
    "https://production-cdn.dr-massive.com/api/page"
    "?device=web_browser&item_detail_expand=all&lang=da"
    "&max_list_prefetch=3&path={path}"
)
CHILDREN_API = (
    "https://production-cdn.dr-massive.com/api/items/{item_id}/children"
    "?device=web_browser&lang=da&page={page}&page_size={page_size}"
)
USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64; rv:127.0) "
    "Gecko/20100101 Firefox/127.0"
)
EPISODE_HREF_RE = re.compile(r"/drtv/(?:se|episode)/[\w~-]+_\d+")


def log(msg):
    print(msg, file=sys.stderr)


def http_get(url):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read().decode("utf-8", errors="replace")


def get_json(url):
    return json.loads(http_get(url))


def api_page(path):
    """Fetch the page API document for a /drtv path like /saeson/x_123."""
    return get_json(PAGE_API.format(path=urllib.parse.quote(path, safe="")))


def page_item(data):
    """Dig the item (show/season) out of a page API response."""
    item = data.get("item")
    if not item:
        entries = data.get("entries") or []
        for entry in entries:
            if isinstance(entry, dict) and entry.get("item"):
                item = entry["item"]
                break
    return item or {}


def episode_urls(item):
    """Episode URLs from a season item, following pagination if needed."""
    episodes = item.get("episodes") or {}
    items = list(episodes.get("items") or [])
    total = (episodes.get("paging") or {}).get("total")
    if total is None:
        total = episodes.get("size")

    # The page API normally inlines the whole season, but page through
    # the children endpoint if this one was truncated.
    if total and len(items) < total and item.get("id"):
        page = 2
        while len(items) < total:
            try:
                more = get_json(CHILDREN_API.format(
                    item_id=item["id"], page=page,
                    page_size=len(items) or 25,
                ))
            except (urllib.error.URLError, ValueError) as exc:
                log(f"warning: could only fetch {len(items)} of {total} "
                    f"episodes ({exc})")
                break
            more_items = more.get("items") or []
            if not more_items:
                break
            items.extend(more_items)
            page += 1

    urls = []
    for ep in items:
        path = ep.get("watchPath") or ep.get("path")
        if path:
            urls.append(BASE + path)
    return urls


def season_list(item):
    """Season items from a show item, oldest first."""
    show = item.get("show") or item
    seasons = ((show.get("seasons") or {}).get("items")) or []
    return sorted(seasons, key=lambda s: s.get("seasonNumber") or 0)


def scrape_html(url):
    """Fallback: pull episode hrefs straight out of the page HTML."""
    html = http_get(url)
    seen = {}
    for match in EPISODE_HREF_RE.finditer(html):
        seen.setdefault(match.group(0), None)
    return ["https://www.dr.dk" + href for href in seen]


def drtv_path(url):
    """Normalize an input URL to the /drtv-relative path the API wants."""
    parsed = urllib.parse.urlparse(url)
    path = parsed.path or url
    if "/drtv/" in path:
        path = path[path.index("/drtv/") + len("/drtv"):]
    return path.rstrip("/")


def collect(url, season_number, list_seasons):
    path = drtv_path(url)

    if path.startswith("/se/") or path.startswith("/episode/"):
        return [BASE + path]

    if path.startswith("/saeson/"):
        return episode_urls(page_item(api_page(path)))

    # Series page: enumerate its seasons.
    item = page_item(api_page(path))
    seasons = season_list(item)

    if list_seasons and seasons:
        for season in seasons:
            log(f"season {season.get('seasonNumber')}: "
                f"{season.get('title')} ({BASE}{season.get('path', '')})")
        return []

    if season_number is not None:
        seasons = [s for s in seasons
                   if s.get("seasonNumber") == season_number]
        if not seasons:
            raise SystemExit(f"error: no season {season_number} found "
                             "(use --list-seasons to see them)")

    if not seasons:
        # Not a show with a season list; maybe the item itself
        # carries the episodes.
        return episode_urls(item)

    urls = []
    for season in seasons:
        season_path = season.get("path")
        if not season_path:
            continue
        found = episode_urls(page_item(api_page(season_path)))
        log(f"season {season.get('seasonNumber')}: {len(found)} episodes")
        urls.extend(found)
    return urls


def default_output(url):
    tail = drtv_path(url).rstrip("/").rsplit("/", 1)[-1]
    return (tail or "drtv-links") + ".txt"


def main():
    parser = argparse.ArgumentParser(
        prog="drtv-links",
        description="Write all episode links of a DRTV series or season "
                    "to a file, one per line (for yt-dlp -a FILE).",
    )
    parser.add_argument("url", help="DRTV series, season or episode URL, "
                        "e.g. https://www.dr.dk/drtv/serie/gurli-gris_7190")
    parser.add_argument("-o", "--output", metavar="FILE",
                        help="output file (default: derived from the URL; "
                        "use '-' for stdout)")
    parser.add_argument("-s", "--season", type=int, metavar="N",
                        help="only this season number (series URLs only)")
    parser.add_argument("--list-seasons", action="store_true",
                        help="list the seasons of a series and exit")
    args = parser.parse_args()

    try:
        urls = collect(args.url, args.season, args.list_seasons)
    except (urllib.error.URLError, ValueError, KeyError) as exc:
        log(f"warning: DRTV API lookup failed ({exc}); "
            "falling back to scraping the page")
        urls = scrape_html(args.url)

    if args.list_seasons:
        return

    if not urls:
        raise SystemExit("error: no episode links found")

    output = args.output or default_output(args.url)
    text = "\n".join(urls) + "\n"
    if output == "-":
        sys.stdout.write(text)
    else:
        with open(output, "w", encoding="utf-8") as handle:
            handle.write(text)
        log(f"wrote {len(urls)} links to {output}")


if __name__ == "__main__":
    main()
