from fastapi import FastAPI, File, UploadFile, HTTPException, BackgroundTasks, WebSocket, WebSocketDisconnect, Request
from fastapi.responses import JSONResponse, FileResponse
from fastapi.middleware.cors import CORSMiddleware
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
from typing import Optional
import uuid
import asyncio
from collections import defaultdict
import logging
import time

warnings.filterwarnings("ignore")

# Ensure logs directory exists
logs_dir = Path(__file__).parent.parent / 'logs'
logs_dir.mkdir(exist_ok=True)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(logs_dir / 'api.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Global progress tracking
progress_tracker = defaultdict(lambda: {"status": "idle", "progress": 0, "message": ""})

# Rate limiting tracking (simple in-memory implementation)
request_history = defaultdict(list)
MAX_REQUESTS_PER_MINUTE = 10
MAX_CONCURRENT_TRANSCRIPTIONS = 3
transcription_semaphore = asyncio.Semaphore(MAX_CONCURRENT_TRANSCRIPTIONS)

# =========================================================
# CONFIGURATION
# =========================================================
MODEL_PATH = str(Path(__file__).parent.parent / "models" / "whisper_backend")
device = 0 if torch.cuda.is_available() else -1
BATCH_SIZE = 16 if device == 0 else 1
CHUNK_LENGTH = 30
NUM_BEAMS = 5
TEMPERATURE = 0.0
MAX_FILE_SIZE = 500 * 1024 * 1024  # 500MB

# =========================================================
# LOAD MODEL
# =========================================================
print(f"Loading model from: {MODEL_PATH}")
print(f"Device: {'GPU' if device == 0 else 'CPU'}")

try:
    asr_pipeline = pipeline(
        "automatic-speech-recognition",
        model=MODEL_PATH,
        device=device,
        return_timestamps=True,
        chunk_length_s=30
    )
    print("[SUCCESS] Model loaded successfully!")
except Exception as e:
    print(f"[ERROR] Error loading model: {e}")
    raise

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
    if file_size > MAX_FILE_SIZE:
        return False, f"File too large (max {MAX_FILE_SIZE/1024/1024:.0f}MB)"
    
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
        print(f"[ERROR] Metadata extraction error: {e}")
        return None

def transcribe_audio_file(audio_path, job_id=None):
    """Transcribe audio with Whisper and progress tracking"""
    try:
        if job_id:
            progress_tracker[job_id] = {"status": "loading", "progress": 10, "message": "Loading audio file..."}
        
        audio, sr = librosa.load(audio_path, sr=16000, mono=True)
        audio = preprocess_audio(audio, sr)
        print(f"[AUDIO] Duration: {len(audio)/sr:.2f}s, RMS: {np.sqrt(np.mean(audio**2)):.4f}")
        
        if job_id:
            progress_tracker[job_id] = {"status": "processing", "progress": 30, "message": "Processing audio..."}
    except Exception as e:
        if job_id:
            progress_tracker[job_id] = {"status": "error", "progress": 0, "message": f"Audio error: {str(e)}"}
        print(f"[ERROR] Audio error: {e}")
        raise
    
    with warnings.catch_warnings():
        warnings.filterwarnings("ignore")
        if job_id:
            progress_tracker[job_id] = {"status": "transcribing", "progress": 50, "message": "Transcribing audio..."}
        
        result = asr_pipeline(
            {"array": audio, "sampling_rate": sr},
            return_timestamps="word",
            chunk_length_s=CHUNK_LENGTH,
            batch_size=BATCH_SIZE,
            generate_kwargs={
                "num_beams": NUM_BEAMS,
                "max_length": 225,
                "temperature": TEMPERATURE,
                "compression_ratio_threshold": 2.4,
                "logprob_threshold": -1.0,
                "no_speech_threshold": 0.6,
            }
        )
        
        if job_id:
            progress_tracker[job_id] = {"status": "finalizing", "progress": 90, "message": "Finalizing transcription..."}
    
    return result

def create_segments_from_chunks(result, max_words_per_segment=10, min_pause_duration=0.3):
    """Create subtitle segments with intelligent pause detection"""
    segments = []
    
    if "chunks" not in result or not result["chunks"]:
        text = result.get("text", "")
        if text.strip():
            words = text.split()
            duration = max(3.0, len(words) / 2.5)
            segments.append({
                "start": 0.0,
                "end": duration,
                "text": text
            })
        return segments
    
    word_chunks = []
    for chunk in result["chunks"]:
        timestamp = chunk.get("timestamp", (0, None))
        text = chunk.get("text", "").strip()
        
        if not text:
            continue
        
        if isinstance(timestamp, (list, tuple)) and len(timestamp) >= 2:
            start = float(timestamp[0]) if timestamp[0] is not None else 0.0
            end = timestamp[1]
            
            if end is None:
                words = text.split()
                estimated_duration = max(0.5, len(words) / 2.5)
                end = start + estimated_duration
            else:
                end = float(end)
        else:
            start = 0.0
            end = 1.0
        
        word_chunks.append({
            "start": start,
            "end": end,
            "text": text
        })
    
    print(f"[PROCESSING] {len(word_chunks)} word chunks from Whisper")
    
    if not word_chunks:
        return segments
    
    current_segment = []
    segment_start = None
    
    for i, chunk in enumerate(word_chunks):
        if segment_start is None:
            segment_start = chunk["start"]
        
        current_segment.append(chunk["text"])
        
        should_break = False
        is_last = (i == len(word_chunks) - 1)
        
        if is_last:
            should_break = True
        else:
            next_chunk = word_chunks[i + 1]
            pause = next_chunk["start"] - chunk["end"]
            
            total_words = sum(len(c.split()) for c in current_segment)
            has_pause = pause >= min_pause_duration
            text = chunk["text"].strip()
            has_punctuation = text and text[-1] in '.!?።'
            too_many_words = total_words >= max_words_per_segment
            
            if has_pause or has_punctuation:
                should_break = True
            elif too_many_words and pause >= min_pause_duration * 0.3:
                should_break = True
            elif total_words >= max_words_per_segment * 1.5:
                should_break = True
        
        if should_break:
            segment_text = " ".join(current_segment).strip()
            segment_text = clean_transcription_text(segment_text)
            segment_end = chunk["end"]
            
            if segment_text:
                segments.append({
                    "start": round(segment_start, 2),
                    "end": round(segment_end, 2),
                    "text": segment_text
                })
            
            current_segment = []
            segment_start = None
    
    # Merge very short segments
    merged = []
    i = 0
    while i < len(segments):
        current = segments[i]
        word_count = len(current["text"].split())
        
        if word_count <= 2 and i < len(segments) - 1:
            next_seg = segments[i + 1]
            gap = next_seg["start"] - current["end"]
            
            if gap < 0.5:
                merged_text = f"{current['text']} {next_seg['text']}"
                merged_text = clean_transcription_text(merged_text)
                merged.append({
                    "start": current["start"],
                    "end": next_seg["end"],
                    "text": merged_text
                })
                i += 2
                continue
        
        merged.append(current)
        i += 1
    
    segments = merged
    
    # Final cleanup
    for i in range(len(segments)):
        seg = segments[i]
        
        if seg["end"] - seg["start"] < 0.2:
            seg["end"] = seg["start"] + 0.2
        
        if i < len(segments) - 1:
            next_seg = segments[i + 1]
            if seg["end"] > next_seg["start"]:
                seg["end"] = next_seg["start"] - 0.05
        
        seg["start"] = round(seg["start"], 2)
        seg["end"] = round(seg["end"], 2)
    
    print(f"[SUCCESS] Created {len(segments)} segments")
    return segments

def create_srt_from_segments(segments):
    """Generate SRT format from segments"""
    srt_lines = []
    for i, seg in enumerate(segments, start=1):
        start = seg.get("start", 0)
        end = seg.get("end", start + 2)
        text = seg.get("text", "").strip()
        
        if not text:
            continue
            
        srt_lines.append(str(i))
        srt_lines.append(f"{format_timestamp(start)} --> {format_timestamp(end)}")
        srt_lines.append(text)
        srt_lines.append("")
    return "\n".join(srt_lines)

def cleanup_file(filepath: str):
    """Background task to cleanup temp files"""
    try:
        if os.path.exists(filepath):
            os.unlink(filepath)
            print(f"[CLEANUP] Cleaned up: {filepath}")
    except Exception as e:
        print(f"[WARNING] Cleanup error: {e}")

async def cleanup_progress(job_id: str, delay: float = 60.0):
    """Remove completed job from progress tracker after delay"""
    await asyncio.sleep(delay)
    progress_tracker.pop(job_id, None)

# =========================================================
# FASTAPI APP
# =========================================================
app = FastAPI(
    title="Afaan Oromo STT API",
    description="AI-powered Speech-to-Text and Subtitle Generation for Afaan Oromo",
    version="1.0.0"
)

# CORS middleware for mobile app integration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Request logging middleware
@app.middleware("http")
async def log_requests(request: Request, call_next):
    start_time = time.time()
    
    # Get client IP
    client_host = request.client.host if request.client else "unknown"
    
    logger.info(f"Request: {request.method} {request.url.path} from {client_host}")
    
    response = await call_next(request)
    
    process_time = time.time() - start_time
    logger.info(f"Completed: {request.method} {request.url.path} - Status: {response.status_code} - Time: {process_time:.2f}s")
    
    response.headers["X-Process-Time"] = str(process_time)
    return response

# Simple rate limiting function
def check_rate_limit(client_ip: str) -> bool:
    """Check if client has exceeded rate limit"""
    now = time.time()
    minute_ago = now - 60
    
    # Clean old requests
    request_history[client_ip] = [
        req_time for req_time in request_history[client_ip]
        if req_time > minute_ago
    ]
    
    # Check limit
    if len(request_history[client_ip]) >= MAX_REQUESTS_PER_MINUTE:
        return False
    
    # Add current request
    request_history[client_ip].append(now)
    return True

# =========================================================
# API ENDPOINTS
# =========================================================
@app.get("/")
async def root():
    """API health check"""
    return {
        "status": "online",
        "service": "Afaan Oromo STT API",
        "version": "1.0.0",
        "device": "GPU" if device == 0 else "CPU",
        "model": "Whisper (Oromo Fine-tuned)"
    }

@app.get("/health")
async def health_check():
    """Detailed health check"""
    return {
        "status": "healthy",
        "model_loaded": asr_pipeline is not None,
        "device": "GPU" if device == 0 else "CPU",
        "cuda_available": torch.cuda.is_available(),
        "max_file_size_mb": MAX_FILE_SIZE / 1024 / 1024
    }

@app.post("/transcribe")
async def transcribe(
    request: Request,
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...)
):
    """
    Transcribe audio file to text
    
    - **file**: Audio file (MP3, WAV, M4A, etc.)
    
    Returns: Transcription text and metadata
    """
    # Get client IP
    client_ip = request.client.host if request.client else "unknown"
    
    # Check rate limit
    if not check_rate_limit(client_ip):
        logger.warning(f"Rate limit exceeded for {client_ip}")
        raise HTTPException(
            status_code=429,
            detail="Too many requests. Please try again in a minute."
        )
    
    # Check concurrent transcriptions (non-blocking)
    if transcription_semaphore.locked():
        logger.warning(f"Max concurrent transcriptions reached")
        raise HTTPException(
            status_code=503,
            detail="Server busy. Please try again later."
        )
    
    temp_file = None
    job_id = str(uuid.uuid4())
    
    try:
        async with transcription_semaphore:
            logger.info(f"Starting transcription job {job_id} from {client_ip}")
            # Initialize progress
            progress_tracker[job_id] = {"status": "uploading", "progress": 5, "message": "Uploading file..."}
            
            # Save uploaded file
            file_ext = Path(file.filename).suffix
            temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=file_ext)
            
            with temp_file as f:
                shutil.copyfileobj(file.file, f)
            
            temp_path = temp_file.name
            
            # Get audio metadata
            audio_metadata = get_audio_metadata(temp_path)
            
            # Validate audio
            valid, msg = validate_audio(temp_path)
            if not valid:
                progress_tracker[job_id] = {"status": "error", "progress": 0, "message": msg}
                background_tasks.add_task(cleanup_file, temp_path)
                raise HTTPException(status_code=400, detail=msg)
            
            # Transcribe with progress tracking
            print(f"[TRANSCRIBE] Processing: {file.filename} (Job: {job_id})")
            result = transcribe_audio_file(temp_path, job_id)
            full_text = result["text"]
            
            # Metadata
            word_count = len(full_text.split())
            char_count = len(full_text)
            
            # Mark as completed
            progress_tracker[job_id] = {"status": "completed", "progress": 100, "message": "Transcription complete!"}
            
            # Cleanup
            background_tasks.add_task(cleanup_file, temp_path)
            asyncio.create_task(cleanup_progress(job_id))
            
            logger.info(f"Completed transcription job {job_id} - {word_count} words, {char_count} chars")
            
            return JSONResponse({
                "success": True,
                "text": full_text,
                "job_id": job_id,
                "metadata": {
                    "word_count": word_count,
                    "character_count": char_count,
                    "filename": file.filename,
                    "duration": audio_metadata["duration"] if audio_metadata else None,
                    "file_size": audio_metadata["size"] if audio_metadata else None,
                    "timestamp": datetime.now().isoformat()
                }
            })
    
    except HTTPException:
        raise
    except Exception as e:
        if temp_file:
            background_tasks.add_task(cleanup_file, temp_file.name)
        progress_tracker[job_id] = {"status": "error", "progress": 0, "message": str(e)}
        logger.error(f"Error in transcription job {job_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        logger.info(f"Transcription job {job_id} ended")

@app.post("/generate-subtitles")
async def generate_subtitles(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    format: str = "srt"
):
    """
    Generate subtitles from audio/video file
    
    - **file**: Audio or video file
    - **format**: Subtitle format (srt or txt)
    
    Returns: Subtitle file and segments
    """
    temp_audio = None
    subtitle_file = None
    
    try:
        # Save uploaded file
        file_ext = Path(file.filename).suffix
        temp_audio = tempfile.NamedTemporaryFile(delete=False, suffix=file_ext)
        
        with temp_audio as f:
            shutil.copyfileobj(file.file, f)
        
        temp_path = temp_audio.name
        
        # Validate audio
        valid, msg = validate_audio(temp_path)
        if not valid:
            background_tasks.add_task(cleanup_file, temp_path)
            raise HTTPException(status_code=400, detail=msg)
        
        # Generate subtitles
        print(f"[SUBTITLES] Generating for: {file.filename}")
        result = transcribe_audio_file(temp_path)
        segments = create_segments_from_chunks(result)
        
        # Create subtitle file
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        subtitle_content = ""
        
        if format.lower() == "srt":
            subtitle_content = create_srt_from_segments(segments)
            subtitle_filename = f"subtitle_{timestamp}.srt"
        else:
            subtitle_content = result["text"]
            subtitle_filename = f"subtitle_{timestamp}.txt"
        
        subtitle_file = tempfile.NamedTemporaryFile(
            delete=False,
            suffix=f".{format.lower()}",
            mode="w",
            encoding="utf-8"
        )
        subtitle_file.write(subtitle_content)
        subtitle_file.close()
        
        # Cleanup audio file immediately
        background_tasks.add_task(cleanup_file, temp_path)
        background_tasks.add_task(cleanup_file, subtitle_file.name)
        
        # Return subtitle file
        return FileResponse(
            path=subtitle_file.name,
            filename=subtitle_filename,
            media_type="text/plain",
            background=background_tasks
        )
    
    except HTTPException:
        raise
    except Exception as e:
        if temp_audio:
            background_tasks.add_task(cleanup_file, temp_audio.name)
        if subtitle_file:
            background_tasks.add_task(cleanup_file, subtitle_file.name)
        print(f"[ERROR] {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/generate-subtitles-json")
async def generate_subtitles_json(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...)
):
    """
    Generate subtitles and return as JSON with segments
    
    - **file**: Audio or video file
    
    Returns: JSON with segments and full text
    """
    temp_file = None
    
    try:
        # Save uploaded file
        file_ext = Path(file.filename).suffix
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=file_ext)
        
        with temp_file as f:
            shutil.copyfileobj(file.file, f)
        
        temp_path = temp_file.name
        
        # Validate audio
        valid, msg = validate_audio(temp_path)
        if not valid:
            background_tasks.add_task(cleanup_file, temp_path)
            raise HTTPException(status_code=400, detail=msg)
        
        # Generate subtitles
        print(f"[SUBTITLES] Generating JSON for: {file.filename}")
        result = transcribe_audio_file(temp_path)
        segments = create_segments_from_chunks(result)
        srt_text = create_srt_from_segments(segments)
        
        # Cleanup
        background_tasks.add_task(cleanup_file, temp_path)
        
        return JSONResponse({
            "success": True,
            "segments": segments,
            "full_text": result["text"],
            "srt": srt_text,
            "metadata": {
                "segment_count": len(segments),
                "filename": file.filename,
                "timestamp": datetime.now().isoformat()
            }
        })
    
    except HTTPException:
        raise
    except Exception as e:
        if temp_file:
            background_tasks.add_task(cleanup_file, temp_file.name)
        print(f"[ERROR] {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.websocket("/live-transcribe")
async def live_transcribe_websocket(websocket: WebSocket):
    """
    WebSocket endpoint for real-time live transcription
    
    Protocol:
    1. Client connects to WebSocket
    2. Client sends audio chunks as binary data
    3. Server processes and returns transcription
    4. Client sends "END" to finalize
    """
    await websocket.accept()
    print("[WEBSOCKET] Client connected for live transcription")
    
    audio_buffer = []
    chunk_count = 0
    
    try:
        while True:
            # Receive audio chunk
            data = await websocket.receive()
            
            if "text" in data:
                # Text message (control signals)
                message = data["text"]
                
                if message == "END":
                    print("[WEBSOCKET] Received END signal")
                    
                    # Process any remaining audio
                    if audio_buffer:
                        try:
                            full_audio = np.concatenate(audio_buffer)
                            temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".wav")
                            
                            import soundfile as sf
                            sf.write(temp_file.name, full_audio, 16000)
                            
                            result = transcribe_audio_file(temp_file.name)
                            
                            await websocket.send_json({
                                "type": "final",
                                "text": result["text"],
                                "complete": True
                            })
                            
                            os.unlink(temp_file.name)
                        except Exception as e:
                            print(f"[ERROR] Final transcription error: {e}")
                            await websocket.send_json({
                                "type": "error",
                                "message": str(e)
                            })
                    
                    break
                
                elif message == "PING":
                    await websocket.send_text("PONG")
            
            elif "bytes" in data:
                # Binary audio data
                audio_chunk = data["bytes"]
                chunk_count += 1
                
                try:
                    # Convert bytes to numpy array
                    audio_data = np.frombuffer(audio_chunk, dtype=np.int16).astype(np.float32) / 32768.0
                    audio_buffer.append(audio_data)
                    
                    print(f"[WEBSOCKET] Received chunk {chunk_count}, size: {len(audio_data)} samples")
                    
                    # Process when we have enough data (every ~3 seconds at 16kHz)
                    if len(audio_buffer) >= 5:  # Adjust threshold as needed
                        try:
                            # Combine chunks
                            combined_audio = np.concatenate(audio_buffer)
                            
                            # Save to temp file
                            temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".wav")
                            
                            import soundfile as sf
                            sf.write(temp_file.name, combined_audio, 16000)
                            
                            # Transcribe
                            result = transcribe_audio_file(temp_file.name)
                            
                            # Send partial result
                            await websocket.send_json({
                                "type": "partial",
                                "text": result["text"],
                                "chunk": chunk_count,
                                "complete": False
                            })
                            
                            # Clean up
                            os.unlink(temp_file.name)
                            
                            # Keep last chunk for context
                            audio_buffer = audio_buffer[-1:]
                            
                        except Exception as e:
                            print(f"[ERROR] Transcription error: {e}")
                            await websocket.send_json({
                                "type": "error",
                                "message": str(e)
                            })
                    
                except Exception as e:
                    print(f"[ERROR] Audio processing error: {e}")
                    await websocket.send_json({
                        "type": "error",
                        "message": f"Audio processing failed: {str(e)}"
                    })
    
    except WebSocketDisconnect:
        print("[WEBSOCKET] Client disconnected")
    except Exception as e:
        print(f"[ERROR] WebSocket error: {e}")
        try:
            await websocket.send_json({
                "type": "error",
                "message": str(e)
            })
        except:
            pass
    finally:
        print(f"[WEBSOCKET] Connection closed. Processed {chunk_count} chunks")

@app.websocket("/progress/{job_id}")
async def progress_websocket(websocket: WebSocket, job_id: str):
    """
    WebSocket endpoint for real-time transcription progress tracking
    
    Protocol:
    1. Client connects with job_id from /transcribe response
    2. Server sends progress updates every 500ms
    3. Connection closes when job completes or errors
    """
    await websocket.accept()
    print(f"[PROGRESS-WS] Client connected for job: {job_id}")
    
    try:
        while True:
            # Get current progress
            progress = progress_tracker.get(job_id, {"status": "unknown", "progress": 0, "message": "Job not found"})
            
            # Send progress update
            await websocket.send_json(progress)
            
            # Close connection if job is completed or errored
            if progress["status"] in ["completed", "error"]:
                print(f"[PROGRESS-WS] Job {job_id} finished with status: {progress['status']}")
                await asyncio.sleep(0.5)
                break
            
            # Wait before next update
            await asyncio.sleep(0.5)
    
    except WebSocketDisconnect:
        print(f"[PROGRESS-WS] Client disconnected for job: {job_id}")
    except Exception as e:
        print(f"[ERROR] Progress WebSocket error: {e}")
    finally:
        print(f"[PROGRESS-WS] Connection closed for job: {job_id}")

@app.get("/progress/{job_id}")
async def get_progress(job_id: str):
    """
    HTTP endpoint to get transcription progress (alternative to WebSocket)
    
    - **job_id**: Job ID from /transcribe response
    
    Returns: Current progress status
    """
    progress = progress_tracker.get(job_id, {"status": "unknown", "progress": 0, "message": "Job not found"})
    return JSONResponse(progress)

# =========================================================
# RUN SERVER
# =========================================================
if __name__ == "__main__":
    uvicorn.run(
        "api:app",
        host="0.0.0.0",
        port=8000,
        reload=False,
        log_level="info"
    )
