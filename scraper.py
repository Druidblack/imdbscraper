# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "playwright",
# ]
# ///
import json
import re
import time
from pathlib import Path
from typing import Dict, List

from playwright.sync_api import sync_playwright


MOVIES_URL = "https://www.imdb.com/chart/top/"
TV_URL = "https://www.imdb.com/chart/toptv/"
PROFILE_DIR = Path("imdb_playwright_profile")


def extract_imdb_id(href: str | None) -> str | None:
    if not href:
        return None
    match = re.search(r"/title/(tt\d+)/", href)
    return match.group(1) if match else None


def clean_title(raw_title: str) -> str:
    return re.sub(r"^\d+\.\s*", "", raw_title).strip()


def clean_rating(raw_rating: str) -> str:
    match = re.search(r"\d+(?:\.\d+)?", raw_rating)
    return match.group(0) if match else raw_rating.strip()


def wait_for_all_items(page, target_count: int = 250, timeout_sec: int = 180) -> int:
    start = time.time()

    while time.time() - start < timeout_sec:
        html = page.content().lower()

        if "not a robot" in html or "javascript is disabled" in html:
            print("IMDb показал страницу проверки.")
            print("Пройдите проверку в открывшемся окне браузера, затем нажмите Enter в консоли...")
            input()
            page.reload(wait_until="domcontentloaded", timeout=120000)

        count = page.locator(".ipc-metadata-list-summary-item").count()
        if count >= target_count:
            return count

        time.sleep(1)

    return page.locator(".ipc-metadata-list-summary-item").count()


def scrape_chart(page, url: str) -> List[Dict[str, str]]:
    page.goto(url, wait_until="domcontentloaded", timeout=120000)

    count = wait_for_all_items(page, target_count=250, timeout_sec=180)
    print(f"Для {url} найдено карточек: {count}")

    items = page.locator(".ipc-metadata-list-summary-item")
    results: List[Dict[str, str]] = []

    for i in range(count):
        item = items.nth(i)

        link_el = item.locator("a.ipc-title-link-wrapper").first
        title_el = item.locator(".ipc-title__text").first
        year_el = item.locator(".cli-title-metadata span").first
        rating_el = item.locator(".ipc-rating-star").first

        href = link_el.get_attribute("href")
        imdb_id = extract_imdb_id(href)

        raw_title = title_el.text_content() if title_el.count() else ""
        raw_year = year_el.text_content() if year_el.count() else ""
        raw_rating = rating_el.text_content() if rating_el.count() else ""

        title = clean_title(raw_title or "")
        year = (raw_year or "").strip()
        rating = clean_rating(raw_rating or "")

        if imdb_id and title and year and rating:
            results.append(
                {
                    "imdb_id": imdb_id,
                    "title": title,
                    "year": year,
                    "rating": rating,
                }
            )

    return results


def save_report(filename: str, source_url: str, items: List[Dict[str, str]]) -> None:
    report = {
        "source": source_url,
        "count": len(items),
        "items": items,
    }

    with open(filename, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)

    print(f"Saved {len(items)} items to {filename}")


def main() -> None:
    with sync_playwright() as p:
        context = p.chromium.launch_persistent_context(
            user_data_dir=str(PROFILE_DIR),
            headless=False,
            viewport={"width": 1600, "height": 1200},
        )

        page = context.pages[0] if context.pages else context.new_page()

        movies = scrape_chart(page, MOVIES_URL)
        save_report("IMDb_top_250_movies.json", MOVIES_URL, movies)

        tv_shows = scrape_chart(page, TV_URL)
        save_report("IMDb_top_250_tv_shows.json", TV_URL, tv_shows)

        context.close()


if __name__ == "__main__":
    main()