"""
Production-Grade Afaan Oromo STT API
Enterprise-ready with monitoring, persistence, and robust error handling
"""
from fastapi import FastAPI, File, UploadFile, HTTPException, BackgroundTasks, WebSocket, WebSocketDisconnect, Request, Depends
from fastapi.responses import JSONResponse, FileResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
import torch
from transformers import pipeline
import tempfile
import os
from pathlib import Path
from datetime import datetime
import warnings
import librosa
import numpy as np
import uvicorn
import shutil
from typing import Optional, Dict, Any
import uuid
import asyncio
from collections import defaultdict
import logging
from logging.handlers import RotatingFileHandler
import time
import traceback

# Import our production modules
from src.config import get_settings, ensure_directories, get_device, get_cors_origins
from src.database import (
    init_db, get_db, TranscriptionService, MetricsService, HealthService, SubtitleHistory
)
from src.monitoring import SystemMonitor, performance_tracker, get_comprehensive_health
from src.privacy import privacy_manager, validate_file_upload
from src.error_tracking import init_sentry, capture_exception, add_breadcrumb, ErrorTracker

warnings.filterwarnings("ignore")

# Load settings
settings = get_settings()
ensure_directories()

# =========================================================
# LOGGING CONFIGURATION
# =========================================================
def setup_logging():
    """Setup production logging with rotation"""
    log_format = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    
    # Create formatters
    formatter = logging.Formatter(log_format)
    
    # File handler with rotation
    file_handler = RotatingFileHandler(
        settings.LOG_FILE,
        maxBytes=settings.LOG_MAX_SIZE_MB * 1024 * 1024,
        backupCount=settings.LOG_BACKUP_COUNT
    )
    file_handler.setFormatter(formatter)
    file_handler.setLevel(logging.INFO)
    
    # Console handler
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(formatter)
    console_handler.setLevel(logging.INFO)
    
    # Configure root logger
    logging.basicConfig(
        level=getattr(logging, settings.LOG_LEVEL),
        handlers=[file_handler, console_handler]
    )
    
    return logging.getLogger(__name__)

logger = setup_logging()

# =========================================================
# GLOBAL STATE
# =========================================================
asr_pipeline = None
progress_tracker = defaultdict(lambda: {"status": "idle", "progress": 0, "message": ""})
request_history = defaultdict(list)
transcription_semaphore = asyncio.Semaphore(3)

# =========================================================
# FASTAPI APP
# =========================================================
app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    description="Production-grade Afaan Oromo Speech-to-Text API with monitoring and persistence",
    docs_url="/docs",
    redoc_url="/redoc"
)

# Add middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=get_cors_origins(),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_middleware(GZipMiddleware, minimum_size=1000)

# =========================================================
# STARTUP & SHUTDOWN
# =========================================================
@app.on_event("startup")
async def startup_event():
    """Initialize on startup"""
    global asr_pipeline
    
    logger.info("="*60)
    logger.info(f"Starting {settings.APP_NAME} v{settings.APP_VERSION}")
    logger.info("="*60)
    
    # Initialize error tracking
    if settings.ENABLE_SENTRY:
        try:
            sentry_enabled = init_sentry(
                dsn=settings.SENTRY_DSN,
                environment=settings.SENTRY_ENVIRONMENT,
                traces_sample_rate=settings.SENTRY_TRACES_SAMPLE_RATE
            )
            if sentry_enabled:
                logger.info("[SENTRY] Error tracking enabled")
        except Exception as e:
            logger.error(f"[SENTRY] Initialization failed: {e}")
    
    # Initialize database
    if settings.ENABLE_DATABASE:
        try:
            init_db()
            logger.info("[DATABASE] Initialized successfully")
        except Exception as e:
            logger.error(f"[DATABASE] Initialization failed: {e}")
            if settings.ENABLE_SENTRY:
                capture_exception(e, context={"component": "database"})
    
    # Start privacy background cleanup
    if settings.ENABLE_AUTO_CLEANUP:
        try:
            privacy_manager.start_background_cleanup(interval_minutes=30)
            logger.info("[PRIVACY] Background cleanup enabled (30min interval)")
        except Exception as e:
            logger.error(f"[PRIVACY] Background cleanup failed to start: {e}")
    
    # Load model
    try:
        device = get_device()
        logger.info(f"[MODEL] Loading from: {settings.MODEL_PATH}")
        logger.info(f"[MODEL] Device: {'GPU' if device >= 0 else 'CPU'}")
        
        asr_pipeline = pipeline(
            "automatic-speech-recognition",
            model=settings.MODEL_PATH,
            device=device,
            return_timestamps=True,
            chunk_length_s=settings.CHUNK_LENGTH
        )
        logger.info("[MODEL] Loaded successfully")
    except Exception as e:
        logger.error(f"[MODEL] Loading failed: {e}")
        logger.error(traceback.format_exc())
        raise
    
    logger.info("="*60)
    logger.info(f"Server: http://{settings.HOST}:{settings.PORT}")
    logger.info(f"Docs: http://{settings.HOST}:{settings.PORT}/docs")
    logger.info(f"Privacy Mode: {'Enabled' if settings.ENABLE_AUTO_CLEANUP else 'Disabled'}")
    logger.info("="*60)


@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on shutdown"""
    logger.info("Shutting down server...")
    
    # Stop background cleanup
    privacy_manager.stop_background_cleanup()
    
    # Cleanup temporary files
    if settings.ENABLE_AUTO_CLEANUP:
        try:
            cleaned = privacy_manager.cleanup_old_files(settings.TEMP_DIR, max_age_hours=0)
            logger.info(f"[CLEANUP] Removed {cleaned} temporary files")
        except Exception as e:
            logger.error(f"[CLEANUP] Error: {e}")


# =========================================================
# UTILITY FUNCTIONS
# =========================================================
def format_timestamp(seconds):
    """Convert seconds to SRT timestamp format"""
    if seconds is None:
        seconds = 0
    ms = int((seconds - int(seconds)) * 1000)
    s = int(seconds)
    h = s // 3600
    m = (s % 3600) // 60
    s = s % 60
    return f"{h:02}:{m:02}:{s:02},{ms:03}"


def validate_audio(audio_path: str):
    """Validate audio file"""
    if not os.path.exists(audio_path):
        return False, "Audio file not found"
    
    file_size = os.path.getsize(audio_path)
    if file_size > settings.MAX_FILE_SIZE:
        return False, f"File too large (max {settings.MAX_FILE_SIZE_MB}MB)"
    
    try:
        audio, sr = librosa.load(audio_path, sr=16000, mono=True, duration=5)
        duration = len(audio) / sr
        
        if duration < 0.5:
            return False, "Audio too short (min 0.5s)"
        
        rms = np.sqrt(np.mean(audio**2))
        if rms < 0.001:
            return False, "Audio appears to be silent or corrupted"
            
    except Exception as e:
        return False, f"Invalid audio format: {str(e)[:50]}"
    
    return True, "Valid"


def preprocess_audio(audio, sr=16000):
    """Audio preprocessing for optimal ASR"""
    audio, _ = librosa.effects.trim(audio, top_db=20)
    rms = np.sqrt(np.mean(audio**2))
    if rms > 1e-3:  # Skip normalization for nearly silent audio
        target_rms = 10**(-20/20)
        audio = audio * (target_rms / rms)
    audio = np.clip(audio, -1.0, 1.0)
    return audio


def clean_transcription_text(text):
    """Clean and normalize transcribed text"""
    if not text:
        return ""
    text = " ".join(text.split())
    if text and text[-1] not in '.!?።':
        text += '.'
    return text


def get_audio_metadata(audio_path):
    """Extract audio file metadata"""
    try:
        audio, sr = librosa.load(audio_path, sr=16000, mono=True)
        duration = len(audio) / sr
        file_size = os.path.getsize(audio_path)
        return {
            "duration": round(duration, 2),
            "size": file_size,
            "sample_rate": sr,
            "channels": 1
        }
    except Exception as e:
        logger.error(f"Metadata extraction error: {e}")
        return {}


def cleanup_temp_file(filepath: str):
    """Cleanup temporary file"""
    try:
        if os.path.exists(filepath):
            os.remove(filepath)
            logger.debug(f"Cleaned up: {filepath}")
    except Exception as e:
        logger.warning(f"Cleanup failed for {filepath}: {e}")


def check_rate_limit(request: Request) -> bool:
    """Check if request should be rate limited"""
    if not settings.RATE_LIMIT_ENABLED:
        return True
    
    client_ip = request.client.host if request.client else "127.0.0.1"
    current_time = time.time()
    
    # Clean old requests
    request_history[client_ip] = [
        t for t in request_history[client_ip]
        if current_time - t < 60
    ]
    
    # Check limit
    if len(request_history[client_ip]) >= settings.MAX_REQUESTS_PER_MINUTE:
        return False
    
    request_history[client_ip].append(current_time)
    return True


# =========================================================
# API ENDPOINTS
# =========================================================

@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "name": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "status": "running",
        "docs": "/docs"
    }


@app.get("/health")
async def health_check(db=Depends(get_db)):
    """Basic health check"""
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "model_loaded": asr_pipeline is not None,
        "device": "GPU" if get_device() >= 0 else "CPU",
        "version": settings.APP_VERSION
    }


@app.get("/health/detailed")
async def detailed_health(db=Depends(get_db)):
    """Comprehensive health check"""
    start_time = time.time()
    
    try:
        health_data = get_comprehensive_health(asr_pipeline, db)
        response_time = time.time() - start_time
        health_data["response_time"] = round(response_time, 3)
        
        return health_data
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return {
            "status": "unhealthy",
            "error": str(e),
            "timestamp": datetime.utcnow().isoformat()
        }


@app.get("/metrics")
async def get_metrics(db=Depends(get_db)):
    """Get API metrics"""
    try:
        metrics_24h = MetricsService.get_summary(db, hours=24)
        performance_stats = performance_tracker.get_stats()
        
        return {
            "timestamp": datetime.utcnow().isoformat(),
            "last_24h": metrics_24h,
            "current_session": performance_stats,
            "system": SystemMonitor.get_full_health()
        }
    except Exception as e:
        logger.error(f"Metrics retrieval failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/history")
async def get_history(limit: int = 100, db=Depends(get_db)):
    """Get transcription history"""
    try:
        records = TranscriptionService.get_recent(db, limit)
        return {
            "count": len(records),
            "records": [
                {
                    "task_id": r.task_id,
                    "filename": r.filename,
                    "duration": r.duration,
                    "word_count": r.word_count,
                    "processing_time": r.processing_time,
                    "success": r.success,
                    "created_at": r.created_at.isoformat()
                }
                for r in records
            ]
        }
    except Exception as e:
        logger.error(f"History retrieval failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/stats")
async def get_stats(db=Depends(get_db)):
    """Get comprehensive statistics"""
    try:
        transcription_stats = TranscriptionService.get_stats(db)
        performance_stats = performance_tracker.get_stats()
        
        return {
            "transcriptions": transcription_stats,
            "performance": performance_stats,
            "timestamp": datetime.utcnow().isoformat()
        }
    except Exception as e:
        logger.error(f"Stats retrieval failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/transcribe")
async def transcribe_audio(
    file: UploadFile = File(...),
    request: Request = None,
    background_tasks: BackgroundTasks = BackgroundTasks(),
    db=Depends(get_db)
):
    """Transcribe audio file"""
    start_time = time.time()
    task_id = str(uuid.uuid4())
    temp_file_path = None
    
    try:
        # Rate limiting
        if not check_rate_limit(request):
            raise HTTPException(status_code=429, detail="Rate limit exceeded")
        
        # Concurrent transcription limit
        if transcription_semaphore.locked():
            raise HTTPException(status_code=503, detail="Server busy, try again later")
        
        async with transcription_semaphore:
            logger.info(f"[{task_id}] Transcription started: {file.filename}")
            
            # Save uploaded file
            temp_file_path = os.path.join(settings.TEMP_DIR, f"{task_id}_{file.filename}")
            with open(temp_file_path, "wb") as buffer:
                shutil.copyfileobj(file.file, buffer)
            
            # Validate
            is_valid, message = validate_audio(temp_file_path)
            if not is_valid:
                raise HTTPException(status_code=400, detail=message)
            
            # Get metadata
            metadata = get_audio_metadata(temp_file_path)
            
            # Transcribe
            audio, sr = librosa.load(temp_file_path, sr=16000, mono=True)
            audio = preprocess_audio(audio)
            
            result = asr_pipeline(
                {"array": audio, "sampling_rate": sr},
                return_timestamps="word",
                chunk_length_s=settings.CHUNK_LENGTH,
                batch_size=settings.BATCH_SIZE,
                generate_kwargs={
                    "num_beams": settings.NUM_BEAMS,
                    "max_length": 225,
                    "temperature": settings.TEMPERATURE,
                    "compression_ratio_threshold": settings.COMPRESSION_RATIO_THRESHOLD,
                    "logprob_threshold": settings.LOGPROB_THRESHOLD,
                    "no_speech_threshold": settings.NO_SPEECH_THRESHOLD,
                }
            )
            text = clean_transcription_text(result.get("text", ""))
            word_count = len(text.split())
            
            processing_time = time.time() - start_time
            
            # Save to database
            if settings.ENABLE_DATABASE:
                TranscriptionService.create(db, task_id, {
                    "filename": file.filename,
                    "file_size": metadata.get("size"),
                    "duration": metadata.get("duration"),
                    "text": text,
                    "word_count": word_count,
                    "processing_time": processing_time,
                    "model": "Whisper",
                    "device": "GPU" if get_device() >= 0 else "CPU",
                    "success": True,
                    "ip_address": request.client.host if request.client else "127.0.0.1",
                    "user_agent": request.headers.get("user-agent")
                })
            
            # Track performance
            performance_tracker.record_request(processing_time, success=True)
            
            # Schedule cleanup
            if background_tasks:
                background_tasks.add_task(cleanup_temp_file, temp_file_path)
            
            logger.info(f"[{task_id}] Completed in {processing_time:.2f}s")
            
            return {
                "task_id": task_id,
                "text": text,
                "word_count": word_count,
                "character_count": len(text),
                "metadata": metadata,
                "processing_time": round(processing_time, 2)
            }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"[{task_id}] Transcription failed: {e}")
        logger.error(traceback.format_exc())
        
        processing_time = time.time() - start_time
        performance_tracker.record_request(processing_time, success=False)
        
        # Save error to database
        if settings.ENABLE_DATABASE:
            try:
                TranscriptionService.create(db, task_id, {
                    "filename": file.filename,
                    "success": False,
                    "error": str(e),
                    "processing_time": processing_time
                })
            except:
                pass
        
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if temp_file_path:
            cleanup_temp_file(temp_file_path)


# =========================================================
# RUN SERVER
# =========================================================
if __name__ == "__main__":
    uvicorn.run(
        "src.api_production:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=settings.RELOAD,
        log_level=settings.LOG_LEVEL.lower(),
        access_log=True,
        workers=settings.WORKERS,
        timeout_keep_alive=settings.KEEP_ALIVE,
        timeout_graceful_shutdown=settings.TIMEOUT
    )
