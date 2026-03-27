"""
PicoClaw Local AI Server — FastAPI + ChromaDB + Ollama
Runs on localhost:7700, provides RAG pipeline for Wubba extension.
"""

import os, platform, psutil, hashlib, time
from pathlib import Path
from typing import Optional
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

import chromadb
import ollama as ollama_client

app = FastAPI(title="PicoClaw", version="1.4.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── ChromaDB setup ──
CHROMA_DIR = os.path.join(str(Path.home()), ".picoclaw", "chromadb")
os.makedirs(CHROMA_DIR, exist_ok=True)
chroma = chromadb.PersistentClient(path=CHROMA_DIR)
collection = chroma.get_or_create_collection("conversations")


# ── Models ──

class IngestRequest(BaseModel):
    provider: str
    messages: list[dict]
    url: Optional[str] = None
    timestamp: Optional[int] = None
    title: Optional[str] = None

class AskRequest(BaseModel):
    question: str
    model: Optional[str] = None

class PullRequest(BaseModel):
    model: str


# ── Helpers ──

def get_gpu_info():
    try:
        import subprocess
        r = subprocess.run(
            ["nvidia-smi", "--query-gpu=name,memory.total", "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=5
        )
        if r.returncode == 0:
            parts = r.stdout.strip().split(", ")
            return {"available": True, "name": parts[0], "vram_mb": int(parts[1])}
    except Exception:
        pass
    # Check Apple Silicon GPU
    if platform.system() == "Darwin" and platform.machine() == "arm64":
        return {"available": True, "name": "Apple Silicon (unified memory)", "vram_mb": None}
    return {"available": False, "name": None, "vram_mb": None}

def recommend_model():
    ram_gb = psutil.virtual_memory().total / (1024**3)
    gpu = get_gpu_info()
    if ram_gb >= 16 or (gpu["available"] and gpu.get("vram_mb", 0) and gpu["vram_mb"] >= 6000):
        return {"model": "llama3.2:3b", "reason": f"{ram_gb:.0f}GB RAM, capable hardware"}
    elif ram_gb >= 8:
        return {"model": "llama3.2:3b", "reason": f"{ram_gb:.0f}GB RAM, should handle 3B model"}
    else:
        return {"model": "llama3.2:1b", "reason": f"{ram_gb:.0f}GB RAM, lightweight model recommended"}


# ── Routes ──

@app.get("/api/health")
def health():
    mem = psutil.virtual_memory()
    return {
        "status": "ok",
        "version": "1.4.0",
        "system": {
            "os": platform.system(),
            "arch": platform.machine(),
            "ram_total_gb": round(mem.total / (1024**3), 1),
            "ram_available_gb": round(mem.available / (1024**3), 1),
            "cpu_count": psutil.cpu_count(),
            "gpu": get_gpu_info(),
        },
        "recommended_model": recommend_model(),
    }

@app.get("/api/models")
def list_models():
    try:
        models = ollama_client.list()
        model_list = [
            {"name": m.model, "size_gb": round(m.size / (1024**3), 2)}
            for m in models.models
        ]
        return {"ollama_running": True, "models": model_list}
    except Exception:
        return {"ollama_running": False, "models": []}

@app.post("/api/models/pull")
def pull_model(req: PullRequest):
    try:
        ollama_client.pull(req.model)
        return {"status": "ok", "model": req.model}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/ingest")
def ingest(req: IngestRequest):
    docs, ids, metas = [], [], []
    for i, msg in enumerate(req.messages):
        content = msg.get("content", "").strip()
        if not content:
            continue
        doc_id = hashlib.md5(f"{req.provider}:{req.timestamp}:{i}:{content[:100]}".encode()).hexdigest()
        docs.append(content)
        ids.append(doc_id)
        metas.append({
            "provider": req.provider,
            "role": msg.get("role", "unknown"),
            "title": req.title or "",
            "url": req.url or "",
            "timestamp": req.timestamp or int(time.time()),
        })

    if docs:
        collection.upsert(documents=docs, ids=ids, metadatas=metas)

    return {
        "chunks_stored": len(docs),
        "total_documents": collection.count(),
    }

@app.get("/api/ingest/stats")
def ingest_stats():
    return {"total_documents": collection.count()}

@app.post("/api/ask")
def ask(req: AskRequest):
    # RAG: retrieve relevant context
    results = collection.query(query_texts=[req.question], n_results=5)
    context_docs = results["documents"][0] if results["documents"] else []
    sources = []
    if results["metadatas"] and results["metadatas"][0]:
        for i, meta in enumerate(results["metadatas"][0]):
            dist = results["distances"][0][i] if results["distances"] else 0
            sources.append({
                "provider": meta.get("provider", ""),
                "title": meta.get("title", ""),
                "distance": round(dist, 4),
            })

    context_block = "\n\n---\n\n".join(context_docs) if context_docs else "No relevant context found."

    prompt = f"""You are PicoClaw, a helpful local AI assistant. Answer the user's question using the context from their saved conversations below.

CONTEXT FROM SAVED CONVERSATIONS:
{context_block}

USER QUESTION: {req.question}

Answer concisely and helpfully. If the context doesn't contain relevant info, say so honestly."""

    model = req.model or recommend_model()["model"]
    try:
        response = ollama_client.chat(model=model, messages=[{"role": "user", "content": prompt}])
        return {
            "answer": response.message.content,
            "model": model,
            "context_used": len(context_docs),
            "sources": sources,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/files/list")
def list_files(path: str = "~"):
    target = os.path.expanduser(path)
    if not os.path.isdir(target):
        raise HTTPException(status_code=404, detail="Directory not found")
    entries = []
    try:
        for entry in os.scandir(target):
            try:
                stat = entry.stat()
                entries.append({
                    "name": entry.name,
                    "is_dir": entry.is_dir(),
                    "size": stat.st_size if not entry.is_dir() else None,
                    "modified": stat.st_mtime,
                })
            except PermissionError:
                continue
    except PermissionError:
        raise HTTPException(status_code=403, detail="Permission denied")
    return {"path": target, "entries": sorted(entries, key=lambda e: (not e["is_dir"], e["name"]))}
