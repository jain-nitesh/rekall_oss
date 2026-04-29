"""
Chat API endpoints for conversational memory (RAG chat).

Allows users to "talk to their memory" with cited, context-aware answers
retrieved from content items, entities, and wiki pages.
"""
from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from pydantic import BaseModel
from typing import Dict, List, Optional
from uuid import UUID

from app.db.session import get_db
from app.models.user import User
from app.api.routes.auth import get_current_user

router = APIRouter(prefix="/chat", tags=["Chat"])


# ===== Request/Response Models =====

class ChatRequest(BaseModel):
    """Send a message to the memory chat."""
    question: str
    conversation_id: Optional[str] = None


class SourceRef(BaseModel):
    """A referenced source in a chat response."""
    id: str
    title: str
    type: str  # content_item, entity


class WikiRef(BaseModel):
    """A referenced wiki page in a chat response."""
    id: str
    title: str
    slug: str = ""


class CitationRef(BaseModel):
    """A citation mapping entry: [TYPE N] -> source details."""
    id: str
    title: str
    type: str  # content_item, entity, wiki_page
    slug: str = ""


class ChatResponse(BaseModel):
    """Response from the memory chat."""
    conversation_id: str
    answer: str
    cited_sources: List[SourceRef] = []
    cited_wiki_pages: List[WikiRef] = []
    citation_map: Dict[str, CitationRef] = {}
    confidence: float = 0.5
    follow_up_suggestions: List[str] = []


class ConversationSummary(BaseModel):
    """Brief conversation info for list views."""
    id: str
    title: Optional[str] = None
    created_at: Optional[str] = None
    updated_at: Optional[str] = None


class ConversationListResponse(BaseModel):
    """Conversation list with count metadata."""
    conversations: List[ConversationSummary]
    total: int
    max_allowed: int


class MessageDetail(BaseModel):
    """A single message in a conversation."""
    id: str
    role: str
    content: str
    referenced_items: list = []
    referenced_wiki_pages: list = []
    created_at: Optional[str] = None


class ConversationDetail(BaseModel):
    """Full conversation with messages."""
    id: str
    title: Optional[str] = None
    created_at: Optional[str] = None
    updated_at: Optional[str] = None
    messages: List[MessageDetail] = []


# ===== Endpoints =====

@router.post("", response_model=ChatResponse)
async def send_message(
    request: ChatRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Send a message to the memory chat.

    Performs multi-source RAG retrieval across content items, entities,
    and wiki pages, then generates a cited answer.

    If conversation_id is provided, continues that conversation.
    Otherwise creates a new conversation.
    """
    if not request.question.strip():
        raise HTTPException(status_code=400, detail="Question cannot be empty")

    from app.services.chat_service import chat, get_conversation_count, MAX_CONVERSATIONS

    # Enforce conversation limit for new conversations
    if not request.conversation_id:
        count = await get_conversation_count(str(current_user.id), db)
        if count >= MAX_CONVERSATIONS:
            raise HTTPException(
                status_code=429,
                detail=f"Conversation limit reached ({MAX_CONVERSATIONS}). Delete existing conversations to create new ones.",
            )

    result = await chat(
        user_id=str(current_user.id),
        question=request.question.strip(),
        conversation_id=request.conversation_id,
        db=db,
    )

    return ChatResponse(
        conversation_id=result['conversation_id'],
        answer=result['answer'],
        cited_sources=[
            SourceRef(id=s['id'], title=s['title'], type=s['type'])
            for s in result.get('cited_sources', [])
        ],
        cited_wiki_pages=[
            WikiRef(id=w['id'], title=w['title'], slug=w.get('slug', ''))
            for w in result.get('cited_wiki_pages', [])
        ],
        citation_map={
            key: CitationRef(id=v['id'], title=v['title'], type=v['type'], slug=v.get('slug', ''))
            for key, v in result.get('citation_map', {}).items()
        },
        confidence=result.get('confidence', 0.5),
        follow_up_suggestions=result.get('follow_up_suggestions', []),
    )


@router.get("/conversations", response_model=ConversationListResponse)
async def list_conversations(
    limit: int = Query(50, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """List the user's chat conversations, most recent first."""
    from app.services.chat_service import get_conversations, get_conversation_count, MAX_CONVERSATIONS

    conversations = await get_conversations(str(current_user.id), db, limit)
    total = await get_conversation_count(str(current_user.id), db)
    return ConversationListResponse(
        conversations=[ConversationSummary(**c) for c in conversations],
        total=total,
        max_allowed=MAX_CONVERSATIONS,
    )


@router.get("/conversations/{conversation_id}", response_model=ConversationDetail)
async def get_conversation(
    conversation_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get a conversation with all its messages."""
    from app.services.chat_service import get_conversation_messages

    result = await get_conversation_messages(str(conversation_id), str(current_user.id), db)
    if not result:
        raise HTTPException(status_code=404, detail="Conversation not found")

    return ConversationDetail(
        id=result['id'],
        title=result['title'],
        created_at=result['created_at'],
        updated_at=result['updated_at'],
        messages=[MessageDetail(**m) for m in result['messages']],
    )


@router.delete("/conversations/{conversation_id}")
async def delete_conversation_endpoint(
    conversation_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Delete a conversation and all its messages."""
    from app.services.chat_service import delete_conversation

    success = await delete_conversation(str(conversation_id), str(current_user.id), db)
    if not success:
        raise HTTPException(status_code=404, detail="Conversation not found")

    return {"status": "deleted", "id": str(conversation_id)}
