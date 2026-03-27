import platform
import psutil
from fastapi import APIRouter

router = APIRouter()

def get_gpu_info():
    try:
        import subprocess
        result = subprocess.run(
            ["nvidia-smi", "--query-gpu=name,memory.total", "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            parts = result.stdout.strip().split(", ")
            return {"available": True, "name": parts[0], "vram_mb": int(parts[1])}
    except Exception:
        pass
    return {"available": False, "name": None, "vram_mb": None}

def recommend_model(ram_gb, gpu):
    if gpu["available"] and (gpu["vram_mb"] or 0) >= 6000:
        return {"model": "llama3.2:3b", "reason": "GPU with 6GB+ VRAM detected"}
    if ram_gb >= 16:
        return {"model": "llama3.2:3b", "reason": "16GB+ RAM available"}
    return {"model": "llama3.2:1b", "reason": "Optimized for available memory"}

@router.get("/health")
async def health():
    mem = psutil.virtual_memory()
    ram_gb = round(mem.total / (1024**3), 1)
    gpu = get_gpu_info()
    return {
        "status": "ok",
        "version": "0.4.0",
        "system": {
            "os": platform.system(),
            "arch": platform.machine(),
            "ram_total_gb": ram_gb,
            "ram_available_gb": round(mem.available / (1024**3), 1),
            "cpu_count": psutil.cpu_count(),
            "gpu": gpu,
        },
        "recommended_model": recommend_model(ram_gb, gpu),
    }
