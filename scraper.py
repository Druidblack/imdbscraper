# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "playwright",
# ]
# ///
import json
import os
import re
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from playwright.sync_api import Browser, BrowserContext, Page, sync_playwright


MOVIES_URL = "https://www.imdb.com/chart/top/"
TV_URL = "https://www.imdb.com/chart/toptv/"

MOVIES_FILE = "IMDb_top_250_movies.json"
TV_FILE = "IMDb_top_250_tv_shows.json"

PROFILE_DIR = Path("imdb_playwright_profile")
TARGET_COUNT = 250

CI_MODE = os.getenv("GITHUB_ACTIONS") == "true" or os.getenv("CI") == "true"


def extract_imdb_id(href: Optional[str]) -> Optional[str]:
    if not href:
        return None

    match = re.search(r"/title/(tt\d+)/", href)
    return match.group(1) if match else None


def clean_title(raw_title: str) -> str:
    return re.sub(r"^\d+\.\s*", "", raw_title).strip()


def clean_rating(raw_rating: str) -> str:
    match = re.search(r"\d+(?:\.\d+)?", raw_rating)
    return match.group(0) if match else raw_rating.strip()


def is_antibot_page(page: Page) -> bool:
    try:
        html = page.content().lower()
    except Exception:
        return False

    markers = [
        "not a robot",
        "verify that you're not a robot",
        "verify you are human",
        "javascript is disabled",
    ]
    return any(marker in html for marker in markers)


def create_context(playwright) -> Tuple[Optional[Browser], BrowserContext]:
    if CI_MODE:
        browser = playwright.chromium.launch(headless=True)
        context = browser.new_context(viewport={"width": 1600, "height": 1200})
        return browser, context

    context = playwright.chromium.launch_persistent_context(
        user_data_dir=str(PROFILE_DIR),
        headless=False,
        viewport={"width": 1600, "height": 1200},
    )
    return None, context


def wait_for_all_items(page: Page, url: str, target_count: int = TARGET_COUNT, timeout_sec: int = 180) -> int:
    start = time.time()
    last_count = -1
    stable_cycles = 0

    while time.time() - start < timeout_sec:
        if is_antibot_page(page):
            if CI_MODE:
                raise RuntimeError(f"IMDb returned an anti-bot page for {url} on CI runner.")
            print("IMDb showed a verification page.")
            print("Complete the check in the opened browser window, then press Enter here...")
            input()
            page.goto(url, wait_until="domcontentloaded", timeout=120000)

        items = page.locator(".ipc-metadata-list-summary-item")
        count = items.count()

        if count >= target_count:
            return count

        try:
            page.evaluate("window.scrollTo(0, document.body.scrollHeight)")
        except Exception:
            pass

        time.sleep(1)

        try:
            page.evaluate("window.scrollTo(0, 0)")
        except Exception:
            pass

        if count == last_count:
            stable_cycles += 1
        else:
            stable_cycles = 0
            last_count = count

        if stable_cycles >= 15 and count > 0:
            break

    return page.locator(".ipc-metadata-list-summary-item").count()


def scrape_chart(page: Page, url: str) -> List[Dict[str, str]]:
    page.goto(url, wait_until="domcontentloaded", timeout=120000)

    count = wait_for_all_items(page, url=url, target_count=TARGET_COUNT, timeout_sec=180)
    print(f"Found {count} cards for {url}")

    items = page.locator(".ipc-metadata-list-summary-item")
    results: List[Dict[str, str]] = []
    seen_ids = set()

    for i in range(count):
        item = items.nth(i)

        link_locator = item.locator("a.ipc-title-link-wrapper")
        title_locator = item.locator(".ipc-title__text")
        year_locator = item.locator(".cli-title-metadata span")
        rating_locator = item.locator(".ipc-rating-star")

        href = link_locator.first.get_attribute("href") if link_locator.count() else None
        imdb_id = extract_imdb_id(href)

        raw_title = title_locator.first.text_content() if title_locator.count() else ""
        raw_year = year_locator.first.text_content() if year_locator.count() else ""
        raw_rating = rating_locator.first.text_content() if rating_locator.count() else ""

        title = clean_title(raw_title or "")
        year = (raw_year or "").strip()
        rating = clean_rating(raw_rating or "")

        if imdb_id and imdb_id not in seen_ids and title and year and rating:
            results.append(
                {
                    "imdb_id": imdb_id,
                    "title": title,
                    "year": year,
                    "rating": rating,
                }
            )
            seen_ids.add(imdb_id)

    return results


def save_report(filename: str, source_url: str, key_name: str, items: List[Dict[str, str]]) -> None:
    report = {
        "source": source_url,
        "count": len(items),
        key_name: items,
    }

    with open(filename, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)

    print(f"Saved {len(items)} items to {filename}")


def main() -> int:
    with sync_playwright() as p:
        browser, context = create_context(p)
        try:
            page = context.pages[0] if context.pages else context.new_page()

            movies = scrape_chart(page, MOVIES_URL)
            save_report(MOVIES_FILE, MOVIES_URL, "movies", movies)

            tv_shows = scrape_chart(page, TV_URL)
            save_report(TV_FILE, TV_URL, "tv_shows", tv_shows)

        finally:
            context.close()
            if browser is not None:
                browser.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())