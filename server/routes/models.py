from fastapi import APIRouter
from pydantic import BaseModel
import ollama as ollama_client

router = APIRouter()

class PullRequest(BaseModel):
    model: str

@router.get("/models")
async def list_models():
    try:
        result = ollama_client.list()
        models = [
            {"name": m.get("name", m.get("model", "")), "size_gb": round(m.get("size", 0) / 1e9, 2)}
            for m in result.get("models", [])
        ]
        return {"ollama_running": True, "models": models}
    except Exception:
        return {"ollama_running": False, "models": []}

@router.post("/models/pull")
async def pull_model(req: PullRequest):
    try:
        ollama_client.pull(req.model)
        return {"status": "ok", "model": req.model}
    except Exception as e:
        return {"status": "error", "error": str(e)}
