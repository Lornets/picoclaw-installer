import os
from pathlib import Path
from fastapi import APIRouter

router = APIRouter()

@router.get("/files/list")
async def list_files(path: str = "~"):
    target = Path(path).expanduser().resolve()
    if not target.exists():
        return {"error": "Path not found", "path": str(target)}
    
    items = []
    try:
        for entry in sorted(target.iterdir()):
            try:
                stat = entry.stat()
                items.append({
                    "name": entry.name,
                    "is_dir": entry.is_dir(),
                    "size": stat.st_size if entry.is_file() else None,
                    "path": str(entry),
                })
            except PermissionError:
                continue
    except PermissionError:
        return {"error": "Permission denied", "path": str(target)}
    
    return {"path": str(target), "items": items[:100]}  # Cap at 100 items
