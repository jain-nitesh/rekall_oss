"""
Social enrichment service for self-entity.

Scrapes public metadata from social media links (LinkedIn, GitHub, Twitter, etc.)
to enrich the user's self-entity with profile information.

Triggered:
- Immediately when user saves personal info (background task)
- Weekly via background_processor refresh cycle
"""
import logging
from datetime import datetime
from typing import Dict, Optional
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.entity import Entity
from app.models.user_preferences import UserPreferences
from app.services.content_fetcher import ContentFetcherService

logger = logging.getLogger(__name__)


async def enrich_self_entity(user_id: str, db: AsyncSession) -> bool:
    """
    Fetch public profile data from the user's social links and enrich
    the self-entity with the scraped information.

    Args:
        user_id: The user's UUID
        db: Database session

    Returns:
        True if enrichment succeeded, False otherwise
    """
    print(f"[ENRICH] Starting self-entity enrichment for user {user_id[:8]}...")

    # Load preferences to get self_entity_id
    prefs_query = select(UserPreferences).where(UserPreferences.user_id == user_id)
    prefs_result = await db.execute(prefs_query)
    prefs = prefs_result.scalar_one_or_none()

    if not prefs or not prefs.self_entity_id:
        print(f"[ENRICH] No self-entity configured for user {user_id[:8]}")
        return False

    # Load the self-entity
    entity_query = select(Entity).where(Entity.id == prefs.self_entity_id)
    entity_result = await db.execute(entity_query)
    entity = entity_result.scalar_one_or_none()

    if not entity:
        print(f"[ENRICH] Self-entity {prefs.self_entity_id} not found")
        return False

    metadata = entity.entity_metadata or {}
    social_links = metadata.get("social_links", {})

    if not social_links:
        print(f"[ENRICH] No social links to enrich for user {user_id[:8]}")
        return False

    print(f"[ENRICH] Found {len(social_links)} social link(s) to fetch")

    # Fetch and extract profile data from each social link
    fetcher = ContentFetcherService()
    enriched_profiles = metadata.get("enriched_profiles", {})

    for platform, url in social_links.items():
        if not url or not url.strip():
            continue

        try:
            print(f"[ENRICH] Fetching {platform}: {url}")
            fetch_result = await fetcher.fetch_url(url.strip())

            profile_data = _extract_profile_data(
                platform=platform,
                url=url,
                title=fetch_result.get("title", ""),
                description=fetch_result.get("description", ""),
                content=fetch_result.get("main_content", ""),
                thumbnail=fetch_result.get("thumbnail_url"),
            )

            if profile_data:
                profile_data["fetched_at"] = datetime.utcnow().isoformat()
                enriched_profiles[platform] = profile_data
                print(f"[ENRICH] {platform}: extracted {list(profile_data.keys())}")
            else:
                print(f"[ENRICH] {platform}: no profile data extracted from response")

        except Exception as e:
            print(f"[ENRICH] Failed to fetch {platform} ({url}): {e}")
            import traceback
            traceback.print_exc()
            enriched_profiles[platform] = {
                "error": str(e)[:200],
                "fetched_at": datetime.utcnow().isoformat(),
            }

    # Update entity metadata with enriched profiles
    # Use dict copy to ensure SQLAlchemy detects the JSONB mutation
    metadata["enriched_profiles"] = enriched_profiles
    entity.entity_metadata = dict(metadata)

    # Build enriched description: user bio + profile summaries
    user_bio = metadata.get("user_bio", "")
    enriched_description = _build_enriched_description(
        name=entity.name,
        user_bio=user_bio,
        enriched_profiles=enriched_profiles,
    )

    if enriched_description:
        entity.description = enriched_description

    # Regenerate embedding with enriched description
    try:
        from app.services.ai_service import AIService
        ai_service = AIService()
        embedding_text = f"{entity.name} (person): {entity.description or ''}"
        entity.embedding = await ai_service.generate_embedding(embedding_text)
    except Exception as e:
        print(f"[ENRICH] Failed to regenerate embedding: {e}")

    # Update refresh timestamp
    prefs.self_entity_last_refreshed_at = datetime.utcnow()

    await db.commit()
    logger.info(f"[ENRICH] Enrichment complete for user {user_id[:8]}")
    return True


def _extract_profile_data(
    platform: str,
    url: str,
    title: str,
    description: str,
    content: str,
    thumbnail: Optional[str],
) -> Dict:
    """
    Extract structured profile data from fetched page metadata.

    Different platforms expose data in different ways via Open Graph tags,
    meta descriptions, and main page content. We parse all available signals
    without any AI calls to keep costs zero.
    """
    data = {}

    if platform == "linkedin":
        data = _extract_linkedin(title, description, content, thumbnail)

    elif platform == "github":
        # GitHub meta: "username - Overview" or repo descriptions
        if description:
            data["bio"] = description[:500]
        if title:
            clean = title.replace(" · GitHub", "").strip()
            if "(" in clean and ")" in clean:
                data["display_name"] = clean.split("(")[1].split(")")[0].strip()
        if thumbnail:
            data["avatar_url"] = thumbnail
        if content:
            for line in content.split("\n"):
                line = line.strip()
                if not line:
                    continue
                if len(line) < 100:
                    if any(kw in line.lower() for kw in ["works at", "company"]):
                        data["company"] = line[:100]
                        break

    elif platform in ("twitter", "x"):
        # Twitter/X OG: "@handle on X" + bio in description
        if description:
            data["bio"] = description[:500]
        if title:
            clean = title.replace(" on X", "").replace(" / X", "").strip()
            data["display_name"] = clean
        if thumbnail:
            data["avatar_url"] = thumbnail

    elif platform == "facebook":
        data = _extract_facebook(title, description, content, thumbnail)

    elif platform == "instagram":
        data = _extract_instagram(title, description, content, thumbnail, url)

    elif platform == "website":
        if title:
            data["site_title"] = title[:200]
        if description:
            data["about"] = description[:500]
        # Try to extract meaningful content from personal site
        if content and len(content) > 50:
            data["content_snippet"] = content[:1000]

    else:
        # Generic fallback for unknown platforms
        if title:
            data["title"] = title[:200]
        if description:
            data["description"] = description[:500]

    return data


def _extract_linkedin(title: str, description: str, content: str, thumbnail: Optional[str]) -> Dict:
    """
    Extract rich profile data from LinkedIn public profile.

    LinkedIn OG title format: "Name - Title - Company | LinkedIn"
    LinkedIn OG description: Usually the 'About' summary or first lines of experience.
    Content: Full page text with experience, education, skills sections.
    """
    data = {}

    # Parse headline from title: "Name - Title - Company | LinkedIn"
    if title:
        clean_title = title.replace(" | LinkedIn", "").strip()
        data["headline"] = clean_title
        # Try to extract structured parts from "Name - Title - Company"
        parts = [p.strip() for p in clean_title.split(" - ") if p.strip()]
        if len(parts) >= 2:
            data["display_name"] = parts[0]
        if len(parts) >= 3:
            data["current_role"] = parts[1]
            data["company"] = parts[2]
        elif len(parts) == 2:
            # Could be "Name - Title at Company" or "Name - Title"
            role_part = parts[1]
            if " at " in role_part:
                role, company = role_part.split(" at ", 1)
                data["current_role"] = role.strip()
                data["company"] = company.strip()
            else:
                data["current_role"] = role_part

    if description:
        data["summary"] = description[:500]
    if thumbnail:
        data["avatar_url"] = thumbnail

    # Deep-parse main_content for experience, education, skills, location
    if content:
        _parse_linkedin_content(content, data)

    return data


def _parse_linkedin_content(content: str, data: Dict) -> None:
    """Parse LinkedIn page content for structured sections."""
    content_lower = content.lower()

    # Extract location - LinkedIn often shows "City, Country" near the top
    # Look for common location patterns in first 500 chars
    top_content = content[:500]
    for line in top_content.split("\n"):
        line = line.strip()
        if not line or len(line) > 80:
            continue
        # Location patterns: contains comma, not too long, near profile info
        if "," in line and len(line) < 50 and not any(kw in line.lower() for kw in [
            "experience", "education", "skill", "http", "linkedin", "connection"
        ]):
            # Heuristic: short line with comma that looks like "City, State/Country"
            parts = line.split(",")
            if len(parts) <= 3 and all(len(p.strip()) < 30 for p in parts):
                if "location" not in data:
                    data["location"] = line[:100]

    # Extract connections/followers count
    import re
    followers_match = re.search(r'(\d[\d,]*)\s*(?:followers|connections)', content_lower)
    if followers_match:
        data["followers"] = followers_match.group(0).strip()

    # Extract experience entries from content
    experiences = _extract_section(content, ["experience"])
    if experiences:
        data["experience"] = experiences[:500]

    # Extract education
    education = _extract_section(content, ["education"])
    if education:
        data["education"] = education[:300]

    # Extract skills
    skills = _extract_section(content, ["skills", "top skills"])
    if skills:
        data["skills"] = skills[:300]

    # Extract certifications/licenses
    certs = _extract_section(content, ["licenses & certifications", "certifications"])
    if certs:
        data["certifications"] = certs[:300]


def _extract_section(content: str, section_names: list) -> Optional[str]:
    """
    Extract a named section from page content.
    Looks for section headers and captures text until the next section.
    """
    content_lower = content.lower()

    for section_name in section_names:
        idx = content_lower.find(section_name)
        if idx == -1:
            continue

        # Move past the section header
        start = idx + len(section_name)
        # Find the next section-like boundary (common LinkedIn section names)
        section_boundaries = [
            "experience", "education", "skills", "top skills",
            "licenses & certifications", "certifications",
            "recommendations", "honors & awards", "publications",
            "volunteer", "projects", "languages", "interests",
            "courses", "organizations", "people also viewed",
            "more activity", "show all"
        ]

        end = len(content)
        for boundary in section_boundaries:
            if boundary.lower() == section_name.lower():
                continue
            next_idx = content_lower.find(boundary, start)
            if next_idx != -1 and next_idx < end:
                end = next_idx

        section_text = content[start:end].strip()
        # Clean up: remove excessive whitespace
        lines = [l.strip() for l in section_text.split("\n") if l.strip()]
        if lines:
            return " | ".join(lines[:10])  # Max 10 lines, pipe-separated

    return None


def _extract_facebook(title: str, description: str, content: str, thumbnail: Optional[str]) -> Dict:
    """
    Extract rich profile data from Facebook public profile.

    Facebook OG title: "Display Name" or "Display Name | Facebook"
    Facebook description: Bio or intro text.
    Content: May contain work, education, location, relationship status.
    """
    data = {}

    if title:
        data["display_name"] = title.replace(" | Facebook", "").replace(" - Facebook", "").strip()
    if description:
        data["bio"] = description[:500]
    if thumbnail:
        data["avatar_url"] = thumbnail

    if content:
        _parse_facebook_content(content, data)

    return data


def _parse_facebook_content(content: str, data: Dict) -> None:
    """Parse Facebook page content for structured profile info."""
    content_lower = content.lower()

    # Facebook profile pages often contain "Works at", "Studied at", "Lives in" etc.
    for line in content.split("\n"):
        line = line.strip()
        if not line or len(line) > 200:
            continue
        line_lower = line.lower()

        if line_lower.startswith("works at ") or line_lower.startswith("worked at "):
            if "workplace" not in data:
                data["workplace"] = line[:150]

        elif line_lower.startswith("studied at ") or line_lower.startswith("went to "):
            if "education" not in data:
                data["education"] = line[:150]

        elif line_lower.startswith("lives in ") or line_lower.startswith("from "):
            if "location" not in data:
                data["location"] = line[:100]

        elif any(kw in line_lower for kw in ["works at", "worked at"]):
            if "workplace" not in data and len(line) < 100:
                data["workplace"] = line[:150]

        elif any(kw in line_lower for kw in ["studied at", "went to"]):
            if "education" not in data and len(line) < 100:
                data["education"] = line[:150]

        elif any(kw in line_lower for kw in ["lives in", "from "]):
            if "location" not in data and len(line) < 80:
                data["location"] = line[:100]

    # Try to extract intro/about section
    intro_idx = content_lower.find("intro")
    if intro_idx != -1:
        intro_text = content[intro_idx + 5:intro_idx + 500].strip()
        lines = [l.strip() for l in intro_text.split("\n") if l.strip() and len(l.strip()) > 3]
        if lines:
            data["intro"] = " | ".join(lines[:5])[:300]


def _extract_instagram(
    title: str, description: str, content: str,
    thumbnail: Optional[str], url: str,
) -> Dict:
    """
    Extract profile data from Instagram public profile.

    Instagram OG title: "Display Name (@username) • Instagram photos and videos"
    Instagram OG description: "Followers, Following, Posts - Bio text"
    Content: Limited (JS-heavy), but Playwright can get bio + highlights.
    """
    import re
    data = {}

    if title:
        clean = title
        # Remove common suffixes
        for suffix in [
            " • Instagram photos and videos",
            " • Instagram",
            " | Instagram",
            " (@",
        ]:
            if suffix == " (@" and suffix in clean:
                # Extract username from "Display Name (@username)"
                name_part = clean.split(" (@")[0].strip()
                handle_part = clean.split("(@")[-1].rstrip(")").rstrip(" ").split(")")[0]
                data["display_name"] = name_part
                data["username"] = f"@{handle_part}" if handle_part else None
                clean = ""
                break
            clean = clean.replace(suffix, "").strip()
        if clean and "display_name" not in data:
            data["display_name"] = clean[:100]

    # Extract username from URL if not found in title
    if "username" not in data and url:
        # https://instagram.com/username or https://www.instagram.com/username/
        url_parts = url.rstrip("/").split("/")
        if url_parts:
            handle = url_parts[-1]
            if handle and handle not in ("instagram.com", "www.instagram.com", ""):
                data["username"] = f"@{handle}"

    if description:
        desc = description
        # Instagram description format: "123 Followers, 456 Following, 78 Posts - Bio text here"
        # Also: "123K Followers, 456 Following, 78 Posts - Bio text"
        stats_match = re.match(
            r'([\d,.KkMm]+)\s*Followers?,?\s*([\d,.KkMm]+)\s*Following,?\s*([\d,.KkMm]+)\s*Posts?\s*[-–—]\s*(.*)',
            desc, re.IGNORECASE | re.DOTALL
        )
        if stats_match:
            data["followers"] = stats_match.group(1).strip()
            data["following"] = stats_match.group(2).strip()
            data["posts"] = stats_match.group(3).strip()
            bio_text = stats_match.group(4).strip()
            if bio_text:
                data["bio"] = bio_text[:500]
        else:
            # Try simpler pattern or just use as bio
            data["bio"] = desc[:500]

    if thumbnail:
        data["avatar_url"] = thumbnail

    # Parse content if available (Playwright may provide more)
    if content:
        _parse_instagram_content(content, data)

    return data


def _parse_instagram_content(content: str, data: Dict) -> None:
    """Parse Instagram page content for additional profile info."""
    import re

    # If we didn't get bio from description, try content
    if "bio" not in data:
        # Look for bio-like text in first part of content
        lines = [l.strip() for l in content[:1000].split("\n") if l.strip()]
        for line in lines:
            # Skip navigation/UI elements
            if len(line) > 20 and len(line) < 300 and not any(kw in line.lower() for kw in [
                "instagram", "sign up", "log in", "followers", "following", "posts",
                "suggested", "cookie", "privacy", "download"
            ]):
                data["bio"] = line[:500]
                break

    # Try to extract follower count from content if not from description
    if "followers" not in data:
        followers_match = re.search(r'([\d,.KkMm]+)\s*[Ff]ollowers', content)
        if followers_match:
            data["followers"] = followers_match.group(1).strip()


def _build_enriched_description(
    name: str,
    user_bio: str,
    enriched_profiles: Dict,
) -> str:
    """
    Build a rich description for the self-entity combining user bio
    and scraped profile data. This text feeds the embedding and chat context,
    so richer = better answers about the user. Zero AI calls here.
    """
    parts = []

    if user_bio:
        parts.append(user_bio)

    for platform, data in enriched_profiles.items():
        if "error" in data:
            continue

        if platform == "linkedin":
            if "headline" in data:
                parts.append(f"LinkedIn: {data['headline']}")
            if "summary" in data:
                parts.append(data["summary"])
            if "current_role" in data:
                role_str = f"Current role: {data['current_role']}"
                if "company" in data:
                    role_str += f" at {data['company']}"
                parts.append(role_str)
            elif "company" in data:
                parts.append(f"Works at {data['company']}")
            if "location" in data:
                parts.append(f"Location: {data['location']}")
            if "experience" in data:
                parts.append(f"Experience: {data['experience']}")
            if "education" in data:
                parts.append(f"Education: {data['education']}")
            if "skills" in data:
                parts.append(f"Skills: {data['skills']}")
            if "certifications" in data:
                parts.append(f"Certifications: {data['certifications']}")
            if "followers" in data:
                parts.append(f"LinkedIn network: {data['followers']}")

        elif platform == "github":
            if "bio" in data:
                parts.append(f"GitHub: {data['bio']}")
            if "company" in data:
                parts.append(f"Works at {data['company']}")

        elif platform in ("twitter", "x"):
            if "bio" in data:
                parts.append(f"Twitter/X: {data['bio']}")

        elif platform == "facebook":
            if "bio" in data:
                parts.append(f"Facebook: {data['bio']}")
            if "workplace" in data:
                parts.append(f"Facebook work: {data['workplace']}")
            if "education" in data:
                parts.append(f"Facebook education: {data['education']}")
            if "location" in data:
                parts.append(f"Facebook location: {data['location']}")
            if "intro" in data:
                parts.append(f"Facebook intro: {data['intro']}")

        elif platform == "instagram":
            if "display_name" in data:
                ig_str = f"Instagram: {data['display_name']}"
                if "username" in data:
                    ig_str += f" ({data['username']})"
                parts.append(ig_str)
            elif "username" in data:
                parts.append(f"Instagram: {data['username']}")
            if "bio" in data:
                parts.append(f"Instagram bio: {data['bio']}")
            if "followers" in data:
                parts.append(f"Instagram followers: {data['followers']}")

        elif platform == "website":
            if "about" in data:
                parts.append(f"Website: {data['about']}")

    if not parts:
        return ""

    return "\n".join(parts)
