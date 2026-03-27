from fastapi import APIRouter
from pydantic import BaseModel
from typing import List, Optional
import hashlib
import time

router = APIRouter()

_collection = None

def get_collection():
    global _collection
    if _collection is None:
        import chromadb
        client = chromadb.PersistentClient(path="./chroma_data")
        _collection = client.get_or_create_collection("conversations")
    return _collection

class Message(BaseModel):
    role: str
    content: str

class IngestRequest(BaseModel):
    provider: str
    messages: List[Message]
    url: Optional[str] = None
    timestamp: Optional[int] = None
    title: Optional[str] = None

@router.post("/ingest")
async def ingest(req: IngestRequest):
    collection = get_collection()
    ts = req.timestamp or int(time.time() * 1000)
    
    # Combine messages into chunks (pairs of user+assistant)
    chunks = []
    for i in range(0, len(req.messages) - 1, 2):
        user_msg = req.messages[i]
        assistant_msg = req.messages[i + 1] if i + 1 < len(req.messages) else None
        text = f"User: {user_msg.content}"
        if assistant_msg:
            text += f"\nAssistant: {assistant_msg.content}"
        chunks.append(text)
    
    # If odd number, add last message
    if len(req.messages) % 2 == 1:
        chunks.append(f"{req.messages[-1].role.title()}: {req.messages[-1].content}")

    ids = []
    for i, chunk in enumerate(chunks):
        doc_id = hashlib.sha256(f"{req.provider}:{ts}:{i}".encode()).hexdigest()[:16]
        ids.append(doc_id)
    
    if chunks:
        collection.upsert(
            ids=ids,
            documents=chunks,
            metadatas=[{
                "provider": req.provider,
                "title": req.title or "",
                "url": req.url or "",
                "timestamp": ts,
                "chunk_index": i,
            } for i in range(len(chunks))],
        )

    return {
        "chunks_stored": len(chunks),
        "total_documents": collection.count(),
    }

@router.get("/ingest/stats")
async def ingest_stats():
    collection = get_collection()
    return {"total_documents": collection.count()}
