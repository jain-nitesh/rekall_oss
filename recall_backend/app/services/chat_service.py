"""
Chat service for conversational memory (RAG chat).

Multi-source retrieval-augmented generation that searches across:
- Content items (raw saved content)
- Entities (knowledge graph nodes)
- Wiki pages (compiled knowledge)

Ranking: Wiki pages > Entities > Content items
(pre-compiled knowledge is highest quality)
"""
import asyncio
from datetime import datetime
from typing import List, Dict, Optional, Tuple
from sqlalchemy import select, text, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.conversation import Conversation, ConversationMessage
from app.models.content_item import ContentItem
from app.models.entity import Entity
from app.models.wiki import WikiPage
from app.services.ai_service import AIService
from app.core.config import settings


# Maximum conversations per user
MAX_CONVERSATIONS = 50
# Context budget (approximate tokens)
MAX_CONTEXT_TOKENS = 6000
# Weight multipliers for ranking different source types
WIKI_WEIGHT = 1.5
ENTITY_WEIGHT = 1.2
CONTENT_WEIGHT = 1.0


async def chat(
    user_id: str,
    question: str,
    conversation_id: Optional[str],
    db: AsyncSession
) -> Dict:
    """
    Process a chat message: retrieve context, generate answer, store messages.

    Args:
        user_id: The user's ID
        question: The user's question
        conversation_id: Existing conversation ID, or None for new conversation
        db: Database session

    Returns:
        {
            'conversation_id': str,
            'answer': str,
            'cited_sources': [{'id': str, 'title': str, 'type': str}],
            'cited_wiki_pages': [{'id': str, 'title': str, 'slug': str}],
            'confidence': float,
            'follow_up_suggestions': [str],
        }
    """
    ai_service = AIService()

    # Generate query embedding
    query_embedding = await ai_service.generate_embedding(question)

    # Retrieve context from all sources in parallel
    content_results, entity_results, wiki_results, self_entity = await asyncio.gather(
        _search_content_items(user_id, query_embedding, db),
        _search_entities(user_id, query_embedding, db),
        _search_wiki_pages(user_id, query_embedding, db),
        _get_self_entity(user_id, db),
    )

    # Rank and assemble context
    context_chunks = _rank_and_assemble(content_results, entity_results, wiki_results)

    # Always inject self-entity at the top of context if it exists
    # (ensures questions about the user are always answerable)
    if self_entity:
        # Remove if already present from similarity search to avoid duplicates
        context_chunks = [c for c in context_chunks if c.get('id') != self_entity['id']]
        context_chunks.insert(0, self_entity)

    # Load conversation history
    conversation_history = []
    if conversation_id:
        conversation_history = await _get_conversation_history(conversation_id, db)

    # Call AI
    result = await ai_service.provider.chat_with_context(
        question=question,
        context_chunks=context_chunks,
        conversation_history=conversation_history,
    )

    # Get or create conversation
    conversation = None
    if conversation_id:
        conversation = await db.get(Conversation, conversation_id)

    if not conversation:
        # Auto-generate title from question
        title = question[:100] if len(question) <= 100 else question[:97] + "..."
        conversation = Conversation(
            user_id=user_id,
            title=title,
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(conversation)
        await db.flush()

    # Store user message
    user_msg = ConversationMessage(
        conversation_id=conversation.id,
        role='user',
        content=question,
        created_at=datetime.utcnow(),
    )
    db.add(user_msg)

    # Build citation map: [TYPE N] -> {id, title, type, slug?}
    # This matches the [TYPE N] notation used in the AI prompt context
    citation_map = {}
    for i, chunk in enumerate(context_chunks):
        source_type = chunk.get('type', 'unknown').upper()
        citation_key = f"[{source_type} {i+1}]"
        citation_map[citation_key] = {
            'id': chunk['id'],
            'title': chunk.get('title', 'Untitled'),
            'type': chunk.get('type', 'content_item'),
            'slug': chunk.get('slug', ''),
        }

    # Build references for the assistant message
    cited_ids = set(result.get('cited_source_ids', []))
    referenced_items = []
    referenced_wiki_pages = []

    for chunk in context_chunks:
        if chunk['id'] in cited_ids:
            if chunk['type'] == 'wiki_page':
                referenced_wiki_pages.append({
                    'id': chunk['id'],
                    'title': chunk['title'],
                    'slug': chunk.get('slug', ''),
                })
            else:
                referenced_items.append({
                    'id': chunk['id'],
                    'title': chunk['title'],
                    'type': chunk['type'],
                })

    # Store assistant message
    assistant_msg = ConversationMessage(
        conversation_id=conversation.id,
        role='assistant',
        content=result['answer'],
        referenced_items=referenced_items,
        referenced_wiki_pages=referenced_wiki_pages,
        created_at=datetime.utcnow(),
    )
    db.add(assistant_msg)

    # Update conversation timestamp
    conversation.updated_at = datetime.utcnow()

    await db.commit()

    return {
        'conversation_id': str(conversation.id),
        'answer': result['answer'],
        'cited_sources': referenced_items,
        'cited_wiki_pages': referenced_wiki_pages,
        'citation_map': citation_map,
        'confidence': result.get('confidence', 0.5),
        'follow_up_suggestions': result.get('follow_up_suggestions', []),
    }


async def _search_content_items(
    user_id: str, embedding: List[float], db: AsyncSession, limit: int = 10
) -> List[Dict]:
    """Search content items by embedding similarity."""
    embedding_str = str(embedding)
    stmt = text("""
        SELECT id, title, COALESCE(detailed_summary, summary) as summary,
               content_type, category,
               1 - (embedding <=> cast(:embedding as vector)) as similarity,
               source_app, url, extracted_content
        FROM content_items
        WHERE user_id = cast(:user_id as uuid)
          AND embedding IS NOT NULL
        ORDER BY embedding <=> cast(:embedding as vector)
        LIMIT :limit
    """)

    result = await db.execute(stmt, {
        'user_id': user_id,
        'embedding': embedding_str,
        'limit': limit,
    })

    items = []
    for row in result.all():
        content_type = row[3]
        has_url = bool(row[7])
        is_user_created = content_type in ('note', 'image', 'video') and not has_url
        source_app = row[6] or 'unknown'

        # Use extracted_content for deeper context, fall back to summary
        extracted = (row[8] or '')[:1000] if len(row) > 8 and row[8] else ''
        summary_text = (row[2] or '')[:500]
        content_text = extracted or summary_text

        # Prefix content with ownership context so the LLM knows the distinction
        if not is_user_created:
            content_text = f"[Saved from {source_app} - not user's own work] {content_text}"

        items.append({
            'id': str(row[0]),
            'title': row[1] or 'Untitled',
            'content': content_text,
            'type': 'content_item',
            'content_type': content_type,
            'category': row[4],
            'similarity': float(row[5]) if row[5] else 0.0,
            'is_user_created': is_user_created,
        })

    return items


async def _search_entities(
    user_id: str, embedding: List[float], db: AsyncSession, limit: int = 5
) -> List[Dict]:
    """Search entities by embedding similarity."""
    embedding_str = str(embedding)
    stmt = text("""
        SELECT id, name, entity_type, description, mention_count,
               1 - (embedding <=> cast(:embedding as vector)) as similarity,
               metadata
        FROM entities
        WHERE user_id = cast(:user_id as uuid)
          AND embedding IS NOT NULL
        ORDER BY embedding <=> cast(:embedding as vector)
        LIMIT :limit
    """)

    result = await db.execute(stmt, {
        'user_id': user_id,
        'embedding': embedding_str,
        'limit': limit,
    })

    entities = []
    for row in result.all():
        metadata = row[6] or {}
        content = f"{row[1]} ({row[2]}): {row[3] or 'No description'}. Mentioned {row[4] or 0} times."

        # For self-entity, include enriched profile data in context
        if metadata.get('is_self'):
            enriched = metadata.get('enriched_profiles', {})
            profile_parts = []
            for platform, data in enriched.items():
                if isinstance(data, dict) and 'error' not in data:
                    for key, val in data.items():
                        if key != 'fetched_at' and key != 'avatar_url' and isinstance(val, str):
                            profile_parts.append(f"{platform} {key}: {val}")
            if profile_parts:
                content += "\nProfile data: " + "; ".join(profile_parts)

            social_links = metadata.get('social_links', {})
            if social_links:
                links_str = ", ".join(f"{k}: {v}" for k, v in social_links.items())
                content += f"\nSocial links: {links_str}"

            content = f"[THIS IS THE APP USER] {content}"

        entities.append({
            'id': str(row[0]),
            'title': row[1],
            'content': content,
            'type': 'entity',
            'entity_type': row[2],
            'similarity': float(row[5]) if row[5] else 0.0,
            'is_self': metadata.get('is_self', False),
        })

    return entities


async def _search_wiki_pages(
    user_id: str, embedding: List[float], db: AsyncSession, limit: int = 5
) -> List[Dict]:
    """Search wiki pages by embedding similarity."""
    embedding_str = str(embedding)
    stmt = text("""
        SELECT id, title, slug, LEFT(content_markdown, 1000) as content,
               confidence_score,
               1 - (content_embedding <=> cast(:embedding as vector)) as similarity
        FROM wiki_pages
        WHERE user_id = cast(:user_id as uuid)
          AND content_embedding IS NOT NULL
          AND status = 'published'
        ORDER BY content_embedding <=> cast(:embedding as vector)
        LIMIT :limit
    """)

    result = await db.execute(stmt, {
        'user_id': user_id,
        'embedding': embedding_str,
        'limit': limit,
    })

    return [
        {
            'id': str(row[0]),
            'title': row[1],
            'slug': row[2],
            'content': row[3] or '',
            'type': 'wiki_page',
            'confidence_score': float(row[4]) if row[4] else 0.0,
            'similarity': float(row[5]) if row[5] else 0.0,
        }
        for row in result.all()
    ]


def _rank_and_assemble(
    content_results: List[Dict],
    entity_results: List[Dict],
    wiki_results: List[Dict],
) -> List[Dict]:
    """
    Rank all results by weighted similarity and assemble context.
    Wiki pages get highest priority, then entities, then raw content.
    """
    all_chunks = []

    for chunk in wiki_results:
        chunk['weighted_score'] = chunk['similarity'] * WIKI_WEIGHT
        all_chunks.append(chunk)

    for chunk in entity_results:
        chunk['weighted_score'] = chunk['similarity'] * ENTITY_WEIGHT
        all_chunks.append(chunk)

    for chunk in content_results:
        chunk['weighted_score'] = chunk['similarity'] * CONTENT_WEIGHT
        all_chunks.append(chunk)

    # Sort by weighted score descending
    all_chunks.sort(key=lambda x: x['weighted_score'], reverse=True)

    # Trim to context budget (approximate: 4 chars ~= 1 token)
    selected = []
    token_count = 0
    for chunk in all_chunks:
        chunk_tokens = len(chunk.get('content', '')) // 4
        if token_count + chunk_tokens > MAX_CONTEXT_TOKENS:
            break
        selected.append(chunk)
        token_count += chunk_tokens

    return selected


async def _get_self_entity(user_id: str, db: AsyncSession) -> Optional[Dict]:
    """
    Load the user's self-entity (if configured) to always include in chat context.
    This ensures questions like 'where do I work?' are answerable.
    """
    from app.models.user_preferences import UserPreferences as UserPreferencesModel

    stmt = text("""
        SELECT e.id, e.name, e.entity_type, e.description, e.mention_count, e.metadata
        FROM entities e
        JOIN user_preferences up ON up.self_entity_id = e.id
        WHERE up.user_id = cast(:user_id as uuid)
    """)

    result = await db.execute(stmt, {'user_id': user_id})
    row = result.first()

    if not row:
        return None

    metadata = row[5] or {}
    content = f"{row[1]} ({row[2]}): {row[3] or 'No description'}."

    # Include enriched profile data
    enriched = metadata.get('enriched_profiles', {})
    profile_parts = []
    for platform, data in enriched.items():
        if isinstance(data, dict) and 'error' not in data:
            for key, val in data.items():
                if key not in ('fetched_at', 'avatar_url') and isinstance(val, str):
                    profile_parts.append(f"{platform} {key}: {val}")
    if profile_parts:
        content += "\nProfile data: " + "; ".join(profile_parts)

    social_links = metadata.get('social_links', {})
    if social_links:
        links_str = ", ".join(f"{k}: {v}" for k, v in social_links.items())
        content += f"\nSocial links: {links_str}"

    content = f"[THIS IS THE APP USER] {content}"

    return {
        'id': str(row[0]),
        'title': row[1],
        'content': content,
        'type': 'entity',
        'entity_type': row[2],
        'similarity': 1.0,  # Always max relevance for self
        'weighted_score': 2.0,  # Highest priority
        'is_self': True,
    }


async def _get_conversation_history(
    conversation_id: str, db: AsyncSession
) -> List[Dict]:
    """Load recent conversation messages for context."""
    stmt = (
        select(ConversationMessage)
        .where(ConversationMessage.conversation_id == conversation_id)
        .order_by(ConversationMessage.created_at.desc())
        .limit(10)
    )
    result = await db.execute(stmt)
    messages = list(reversed(result.scalars().all()))

    return [
        {'role': msg.role, 'content': msg.content}
        for msg in messages
    ]


async def get_conversation_count(user_id: str, db: AsyncSession) -> int:
    """Get total number of conversations for a user."""
    stmt = select(func.count(Conversation.id)).where(Conversation.user_id == user_id)
    result = await db.execute(stmt)
    return result.scalar() or 0


async def get_conversations(user_id: str, db: AsyncSession, limit: int = 50) -> List[Dict]:
    """List user's conversations."""
    stmt = (
        select(Conversation)
        .where(Conversation.user_id == user_id)
        .order_by(Conversation.updated_at.desc())
        .limit(limit)
    )
    result = await db.execute(stmt)
    conversations = result.scalars().all()

    return [
        {
            'id': str(c.id),
            'title': c.title,
            'created_at': c.created_at.isoformat() if c.created_at else None,
            'updated_at': c.updated_at.isoformat() if c.updated_at else None,
        }
        for c in conversations
    ]


async def get_conversation_messages(
    conversation_id: str, user_id: str, db: AsyncSession
) -> Optional[Dict]:
    """Get a conversation with its messages."""
    conversation = await db.get(Conversation, conversation_id)
    if not conversation or str(conversation.user_id) != user_id:
        return None

    stmt = (
        select(ConversationMessage)
        .where(ConversationMessage.conversation_id == conversation_id)
        .order_by(ConversationMessage.created_at.asc())
    )
    result = await db.execute(stmt)
    messages = result.scalars().all()

    return {
        'id': str(conversation.id),
        'title': conversation.title,
        'created_at': conversation.created_at.isoformat() if conversation.created_at else None,
        'updated_at': conversation.updated_at.isoformat() if conversation.updated_at else None,
        'messages': [
            {
                'id': str(m.id),
                'role': m.role,
                'content': m.content,
                'referenced_items': m.referenced_items or [],
                'referenced_wiki_pages': m.referenced_wiki_pages or [],
                'created_at': m.created_at.isoformat() if m.created_at else None,
            }
            for m in messages
        ],
    }


async def delete_conversation(
    conversation_id: str, user_id: str, db: AsyncSession
) -> bool:
    """Delete a conversation and all its messages."""
    conversation = await db.get(Conversation, conversation_id)
    if not conversation or str(conversation.user_id) != user_id:
        return False

    await db.delete(conversation)
    await db.commit()
    return True
