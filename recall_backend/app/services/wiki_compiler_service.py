"""
Wiki compiler service.

Compiles AI-synthesized wiki pages from multiple content items about an entity.
Core of the LLM Wiki pattern: "compilation over search, queries compound."

Handles:
- Auto-creation when entity reaches 3+ mentions
- Marking pages stale when new content references their entity
- Compiling/recompiling wiki pages via AI provider
- Contradiction detection across sources
- Backlink extraction for cross-references
"""
import re
from datetime import datetime
from typing import List, Dict, Optional, Tuple
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.entity import Entity, ContentEntity, EntityRelationship
from app.models.content_item import ContentItem
from app.models.wiki import WikiPage, WikiBacklink, WikiContradiction
from app.services.ai_service import AIService
from app.core.config import settings


async def check_and_create_wiki_page(entity_id: str, user_id: str, db: AsyncSession) -> Optional[WikiPage]:
    """
    Check if an entity qualifies for a wiki page and create one if needed.

    Wiki pages are only created for topic and concept entities (2+ mentions).
    Other entity types (person, company, technology, etc.) do NOT get wiki pages.

    Called after entity extraction completes. If the entity already has a wiki page,
    marks it as stale for recompilation.

    Returns:
        WikiPage if created or marked stale, None otherwise.
    """
    entity = await db.get(Entity, entity_id)
    if not entity:
        return None

    # Wiki pages for topics/concepts at 2+ mentions, and person/place/company/technology at 1+ mentions
    low_threshold_types = ('person', 'place', 'company', 'technology')
    high_threshold_types = ('topic', 'concept')
    if entity.entity_type not in low_threshold_types and entity.entity_type not in high_threshold_types:
        # But still check if this entity is related to any existing topic wiki pages
        # and mark those as stale (new content about a related entity arrived)
        await _mark_related_topic_pages_stale(entity, user_id, db)
        return None

    # Check if wiki page already exists for this entity
    stmt = select(WikiPage).where(
        (WikiPage.entity_id == entity_id) &
        (WikiPage.user_id == user_id)
    )
    result = await db.execute(stmt)
    existing_page = result.scalar_one_or_none()

    if existing_page:
        # If published, return it for incremental patching (caller handles patch)
        # If already stale or draft, just return it
        return existing_page

    mention_count = entity.mention_count or 0
    min_mentions = 1 if entity.entity_type in low_threshold_types else 2
    if mention_count < min_mentions:
        return None

    # Create wiki page
    slug = _generate_slug(entity.name)
    wiki_page = WikiPage(
        user_id=user_id,
        entity_id=entity_id,
        title=entity.name,
        slug=slug,
        status='draft',
        source_count=mention_count,
        confidence_score=0.0,
        created_at=datetime.utcnow(),
        updated_at=datetime.utcnow(),
    )
    db.add(wiki_page)
    await db.commit()
    await db.refresh(wiki_page)

    print(f"  [WIKI] Created draft page '{entity.name}' ({entity.entity_type}, slug: {slug}, {mention_count} mentions)")
    return wiki_page


async def _mark_related_topic_pages_stale(entity: Entity, user_id: str, db: AsyncSession):
    """
    When a non-topic entity gets new content, mark any related topic/concept
    wiki pages as stale so they get recompiled with the new information.
    """
    # Find topic/concept entities related to this entity
    stmt = select(EntityRelationship.target_entity_id).where(
        (EntityRelationship.user_id == user_id) &
        (EntityRelationship.source_entity_id == entity.id)
    ).union(
        select(EntityRelationship.source_entity_id).where(
            (EntityRelationship.user_id == user_id) &
            (EntityRelationship.target_entity_id == entity.id)
        )
    )
    result = await db.execute(stmt)
    related_ids = [row[0] for row in result.all()]

    if not related_ids:
        return

    # Find wiki pages for those related topic/concept entities
    wiki_stmt = select(WikiPage).join(Entity, WikiPage.entity_id == Entity.id).where(
        (WikiPage.user_id == user_id) &
        (WikiPage.entity_id.in_(related_ids)) &
        (Entity.entity_type.in_(['topic', 'concept'])) &
        (WikiPage.status == 'published')
    )
    wiki_result = await db.execute(wiki_stmt)
    pages = wiki_result.scalars().all()

    for page in pages:
        page.status = 'stale'
        page.updated_at = datetime.utcnow()
        print(f"  [WIKI] Marked related topic page '{page.title}' as STALE (entity '{entity.name}' updated)")

    if pages:
        await db.commit()


async def compile_wiki_page(wiki_page_id: str, db: AsyncSession) -> bool:
    """
    Compile or recompile a wiki page by synthesizing all related content.

    Gathers all content items linked to the wiki page's entity,
    sends them to the AI for synthesis, and updates the page.

    Returns:
        True if compilation succeeded, False otherwise.
    """
    wiki_page = await db.get(WikiPage, wiki_page_id)
    if not wiki_page:
        print(f"[ERROR] Wiki page {wiki_page_id} not found")
        return False

    entity = await db.get(Entity, wiki_page.entity_id) if wiki_page.entity_id else None
    if not entity:
        print(f"[ERROR] Entity not found for wiki page '{wiki_page.title}'")
        return False

    print(f"[WIKI] Compiling page '{wiki_page.title}'...")

    try:
        ai_service = AIService()

        # Gather all content items linked to this entity AND related subtopics
        sources, self_entity_name, subtopics = await _gather_sources_with_subtopics(
            str(entity.id), entity.entity_type, str(wiki_page.user_id), db
        )
        if not sources:
            print(f"  [WARN] No sources found for topic '{entity.name}'")
            return False

        print(f"  Found {len(sources)} source content items, {len(subtopics)} subtopics")

        # Call AI for compilation with subtopics
        compilation = await ai_service.provider.compile_wiki_page(
            entity_name=entity.name,
            entity_type=entity.entity_type,
            sources=sources,
            existing_wiki_content=wiki_page.content_markdown,
            self_entity_name=self_entity_name,
            subtopics=subtopics,
        )

        content_markdown = compilation.get('content_markdown', '')
        if not content_markdown or len(content_markdown) < 50:
            print(f"  [WARN] AI returned insufficient content")
            return False

        # Update wiki page
        wiki_page.content_markdown = content_markdown
        wiki_page.confidence_score = min(1.0, 0.3 + (len(sources) * 0.07))
        wiki_page.source_count = len(sources)
        wiki_page.status = 'published'
        wiki_page.patch_count = 0
        wiki_page.compilation_mode = 'full'
        wiki_page.last_compiled_at = datetime.utcnow()
        wiki_page.updated_at = datetime.utcnow()

        # Generate embedding for the wiki page content
        try:
            embedding_text = f"{wiki_page.title}: {content_markdown[:2000]}"
            embedding = await ai_service.generate_embedding(embedding_text)
            wiki_page.content_embedding = embedding
        except Exception as e:
            print(f"  [WARN] Embedding generation failed: {e}")

        # Process contradictions
        await _process_contradictions(
            wiki_page=wiki_page,
            contradictions=compilation.get('contradictions', []),
            sources=sources,
            db=db
        )

        # Process backlinks
        await _process_backlinks(
            wiki_page=wiki_page,
            backlink_names=compilation.get('backlinks', []),
            sources=sources,
            db=db
        )

        await db.commit()
        print(f"  [OK] Wiki page '{wiki_page.title}' compiled ({len(content_markdown)} chars, confidence: {wiki_page.confidence_score:.2f})")
        return True

    except Exception as e:
        print(f"  [ERROR] Wiki compilation failed for '{wiki_page.title}': {e}")
        import traceback
        traceback.print_exc()
        return False


async def compile_stale_pages(max_pages: int = 2) -> int:
    """
    Compile stale wiki pages. Called periodically by background processor.

    Returns:
        Number of pages compiled.
    """
    from app.db.session import AsyncSessionLocal

    async with AsyncSessionLocal() as db:
        # Find stale or draft pages
        stmt = select(WikiPage).where(
            WikiPage.status.in_(['stale', 'draft'])
        ).order_by(
            # Prioritize stale (recompile) over draft (first compile)
            WikiPage.status.desc(),
            WikiPage.updated_at.asc()
        ).limit(max_pages)

        result = await db.execute(stmt)
        pages = result.scalars().all()

        if not pages:
            return 0

        compiled = 0
        for page in pages:
            success = await compile_wiki_page(str(page.id), db)
            if success:
                compiled += 1

        return compiled


async def patch_wiki_page(wiki_page_id: str, new_content_item_id: str, db: AsyncSession) -> bool:
    """
    Incrementally patch a wiki page with a single new content item.
    Cheaper than full recompilation — sends existing wiki + 1 source to LLM.

    Returns:
        True if patch succeeded, False otherwise.
    """
    wiki_page = await db.get(WikiPage, wiki_page_id)
    if not wiki_page or not wiki_page.content_markdown:
        return False

    content_item = await db.get(ContentItem, new_content_item_id)
    if not content_item:
        return False

    print(f"[WIKI] Patching page '{wiki_page.title}' with new source '{content_item.title}'...")

    try:
        ai_service = AIService()

        new_source = {
            'title': content_item.title or 'Untitled',
            'summary': content_item.summary or '',
            'content': (content_item.extracted_content or content_item.detailed_summary or '')[:1000],
            'created_at': content_item.created_at.isoformat() if content_item.created_at else 'unknown',
        }

        result = await ai_service.provider.patch_wiki_page(
            existing_content=wiki_page.content_markdown,
            new_source=new_source,
            entity_name=wiki_page.title,
        )

        patched_content = result.get('content_markdown', '')
        if not patched_content or len(patched_content) < 50:
            print(f"  [WARN] Patch returned insufficient content, skipping")
            return False

        # Update wiki page
        wiki_page.content_markdown = patched_content
        wiki_page.source_count = (wiki_page.source_count or 0) + 1
        wiki_page.confidence_score = min(1.0, 0.3 + ((wiki_page.source_count or 1) * 0.07))
        wiki_page.patch_count = (wiki_page.patch_count or 0) + 1
        wiki_page.compilation_mode = 'incremental'
        wiki_page.status = 'published'
        wiki_page.last_compiled_at = datetime.utcnow()
        wiki_page.updated_at = datetime.utcnow()

        # Regenerate embedding
        try:
            embedding_text = f"{wiki_page.title}: {patched_content[:2000]}"
            embedding = await ai_service.generate_embedding(embedding_text)
            wiki_page.content_embedding = embedding
        except Exception as e:
            print(f"  [WARN] Embedding generation failed: {e}")

        # Check if drift prevention threshold hit
        if wiki_page.patch_count >= 10:
            wiki_page.status = 'stale'
            print(f"  [WIKI] Patch count reached 10, marking as stale for full recompile")

        await db.commit()
        changed = result.get('changed_sections', [])
        print(f"  [OK] Patched '{wiki_page.title}' (changed: {changed})")
        return True

    except Exception as e:
        print(f"  [ERROR] Wiki patch failed for '{wiki_page.title}': {e}")
        import traceback
        traceback.print_exc()
        return False


async def _gather_sources_with_subtopics(
    entity_id: str, entity_type: str, user_id: str, db: AsyncSession
) -> Tuple[List[Dict], Optional[str], List[Dict]]:
    """
    Gather all content items linked to a topic/concept entity AND its related
    subtopic entities. Returns sources, self_entity_name, and subtopic list.

    For topic wiki pages, this pulls in content from related concepts/technologies
    to give the wiki page broader coverage organized by subtopics.
    """
    from app.models.user_preferences import UserPreferences as UserPreferencesModel

    # 1. Get content directly linked to this topic entity
    stmt = (
        select(ContentItem)
        .join(ContentEntity, ContentEntity.content_item_id == ContentItem.id)
        .where(
            (ContentEntity.entity_id == entity_id) &
            (ContentItem.user_id == user_id)
        )
        .order_by(ContentItem.created_at.asc())
        .limit(30)
    )
    result = await db.execute(stmt)
    direct_items = result.scalars().all()
    seen_item_ids = {str(item.id) for item in direct_items}

    # 2. Find related entities (subtopics) via EntityRelationship
    subtopics = []
    related_items = []

    rel_stmt = select(
        EntityRelationship.target_entity_id,
        EntityRelationship.source_entity_id,
        EntityRelationship.relationship_type,
    ).where(
        (EntityRelationship.user_id == user_id) &
        (
            (EntityRelationship.source_entity_id == entity_id) |
            (EntityRelationship.target_entity_id == entity_id)
        )
    )
    rel_result = await db.execute(rel_stmt)
    relationships = rel_result.all()

    related_entity_ids = set()
    for target_id, source_id, rel_type in relationships:
        other_id = target_id if str(source_id) == entity_id else source_id
        related_entity_ids.add(other_id)

    # Load related entities and filter to useful subtopic types
    for rel_entity_id in related_entity_ids:
        rel_entity = await db.get(Entity, rel_entity_id)
        if not rel_entity:
            continue
        # Subtopics can be concepts, technologies, or other topics
        if rel_entity.entity_type in ('concept', 'technology', 'topic'):
            subtopics.append({
                'name': rel_entity.name,
                'type': rel_entity.entity_type,
                'description': rel_entity.description or '',
                'mention_count': rel_entity.mention_count or 0,
            })

            # Get content items linked to this subtopic entity (not already included)
            sub_filters = [
                ContentEntity.entity_id == rel_entity_id,
                ContentItem.user_id == user_id,
            ]
            if seen_item_ids:
                sub_filters.append(ContentItem.id.notin_(seen_item_ids))
            sub_stmt = (
                select(ContentItem)
                .join(ContentEntity, ContentEntity.content_item_id == ContentItem.id)
                .where(*sub_filters)
                .order_by(ContentItem.created_at.asc())
                .limit(10)
            )
            sub_result = await db.execute(sub_stmt)
            for item in sub_result.scalars().all():
                if str(item.id) not in seen_item_ids:
                    related_items.append((item, rel_entity.name))
                    seen_item_ids.add(str(item.id))

    # 3. Get self-entity name
    prefs_stmt = select(UserPreferencesModel.self_entity_id).where(
        UserPreferencesModel.user_id == user_id
    )
    prefs_result = await db.execute(prefs_stmt)
    self_entity_id = prefs_result.scalar_one_or_none()

    self_entity_name = None
    if self_entity_id:
        self_entity = await db.get(Entity, self_entity_id)
        if self_entity:
            self_entity_name = self_entity.name

    # 4. Build sources list
    def _make_source(item, subtopic_label=None):
        content_type_val = item.content_type.value if hasattr(item, 'content_type') and item.content_type else 'url'
        is_user_created = content_type_val in ('note', 'image', 'video') and not item.url
        source_label = "USER_CREATED" if is_user_created else f"CURATED_FROM:{item.source_app or 'external'}"

        source = {
            'id': str(item.id),
            'title': item.title or 'Untitled',
            'summary': item.detailed_summary or item.summary or '',
            'content': (item.extracted_content or item.detailed_summary or item.summary or '')[:2000],
            'created_at': item.created_at.isoformat() if item.created_at else 'unknown',
            'ownership': source_label,
            'source_app': item.source_app or 'unknown',
            'is_user_created': is_user_created,
        }
        if subtopic_label:
            source['subtopic'] = subtopic_label
        return source

    sources = [_make_source(item) for item in direct_items]
    sources.extend(_make_source(item, subtopic) for item, subtopic in related_items)

    # Cap total sources
    sources = sources[:40]

    # Sort subtopics by mention count (most referenced first)
    subtopics.sort(key=lambda s: s['mention_count'], reverse=True)

    return sources, self_entity_name, subtopics


async def _process_contradictions(
    wiki_page: WikiPage,
    contradictions: List[Dict],
    sources: List[Dict],
    db: AsyncSession
):
    """Process and store detected contradictions."""
    if not contradictions:
        return

    for c in contradictions[:10]:  # Max 10 contradictions per page
        claim_a = c.get('claim_a', '')
        claim_b = c.get('claim_b', '')
        if not claim_a or not claim_b:
            continue

        # Map source indices to content item IDs
        source_a_idx = c.get('source_a_idx', 0) - 1  # 1-indexed from AI
        source_b_idx = c.get('source_b_idx', 0) - 1

        source_a_id = None
        source_b_id = None
        if 0 <= source_a_idx < len(sources):
            source_a_id = sources[source_a_idx].get('id')
        if 0 <= source_b_idx < len(sources):
            source_b_id = sources[source_b_idx].get('id')

        contradiction = WikiContradiction(
            wiki_page_id=wiki_page.id,
            claim_a=claim_a[:1000],
            source_a_id=source_a_id,
            claim_b=claim_b[:1000],
            source_b_id=source_b_id,
            status='open',
            created_at=datetime.utcnow(),
        )
        db.add(contradiction)

    print(f"  Stored {len(contradictions)} contradiction(s)")


async def _process_backlinks(
    wiki_page: WikiPage,
    backlink_names: List[str],
    sources: List[Dict],
    db: AsyncSession
):
    """Process and store backlinks (references to other entities/wiki pages)."""
    if not backlink_names:
        return

    # Clear existing backlinks for this page (will be rebuilt)
    stmt = select(WikiBacklink).where(WikiBacklink.wiki_page_id == wiki_page.id)
    result = await db.execute(stmt)
    existing = result.scalars().all()
    for bl in existing:
        await db.delete(bl)

    # Add backlinks from source content items
    for source in sources:
        backlink = WikiBacklink(
            wiki_page_id=wiki_page.id,
            source_type='content_item',
            source_id=source['id'],
            context_snippet=source.get('title', '')[:200],
            created_at=datetime.utcnow(),
        )
        db.add(backlink)

    # Add backlinks to other wiki pages that match entity names
    for name in backlink_names[:20]:
        # Find wiki page for this entity name
        entity_stmt = select(WikiPage).where(
            (WikiPage.user_id == wiki_page.user_id) &
            (WikiPage.title.ilike(name)) &
            (WikiPage.id != wiki_page.id)
        )
        result = await db.execute(entity_stmt)
        linked_page = result.scalar_one_or_none()
        if linked_page:
            backlink = WikiBacklink(
                wiki_page_id=wiki_page.id,
                source_type='wiki_page',
                source_id=linked_page.id,
                context_snippet=f"References {linked_page.title}",
                created_at=datetime.utcnow(),
            )
            db.add(backlink)

    print(f"  Stored {len(sources)} source backlinks + cross-references")


def _generate_slug(name: str) -> str:
    """Generate a URL-safe slug from entity name."""
    slug = name.lower().strip()
    slug = re.sub(r'[^a-z0-9\s-]', '', slug)
    slug = re.sub(r'[\s]+', '-', slug)
    slug = re.sub(r'-+', '-', slug)
    return slug[:300]
