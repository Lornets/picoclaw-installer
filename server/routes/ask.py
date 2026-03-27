from fastapi import APIRouter
from pydantic import BaseModel
from typing import Optional
import ollama as ollama_client

router = APIRouter()

# Lazy ChromaDB init
_collection = None

def get_collection():
    global _collection
    if _collection is None:
        import chromadb
        client = chromadb.PersistentClient(path="./chroma_data")
        _collection = client.get_or_create_collection("conversations")
    return _collection

class AskRequest(BaseModel):
    question: str
    model: Optional[str] = None
    n_results: int = 5

@router.post("/ask")
async def ask(req: AskRequest):
    collection = get_collection()
    model = req.model or "llama3.2:1b"

    # RAG: retrieve relevant context
    sources = []
    context_text = ""
    if collection.count() > 0:
        results = collection.query(query_texts=[req.question], n_results=min(req.n_results, collection.count()))
        docs = results.get("documents", [[]])[0]
        metas = results.get("metadatas", [[]])[0]
        distances = results.get("distances", [[]])[0]
        context_text = "\n\n".join(docs)
        for meta, dist in zip(metas, distances):
            sources.append({
                "provider": meta.get("provider", "unknown"),
                "title": meta.get("title", ""),
                "distance": round(dist, 4),
            })

    prompt = f"""Use the following conversation history as context to answer the question.
If the context doesn't contain relevant information, say so.

Context:
{context_text}

Question: {req.question}

Answer:"""

    response = ollama_client.chat(model=model, messages=[{"role": "user", "content": prompt}])

    return {
        "answer": response["message"]["content"],
        "model": model,
        "context_used": len(sources),
        "sources": sources,
    }
