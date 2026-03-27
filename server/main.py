"""
PicoClaw Local AI Server
FastAPI server providing RAG pipeline, local LLM queries, and system info.
Runs on localhost:7700
"""

import os
import platform
import psutil
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(title="PicoClaw", version="0.4.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Routes ──

from routes.health import router as health_router
from routes.ask import router as ask_router
from routes.ingest import router as ingest_router
from routes.models import router as models_router
from routes.files import router as files_router

app.include_router(health_router, prefix="/api")
app.include_router(ask_router, prefix="/api")
app.include_router(ingest_router, prefix="/api")
app.include_router(models_router, prefix="/api")
app.include_router(files_router, prefix="/api")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=7700)
