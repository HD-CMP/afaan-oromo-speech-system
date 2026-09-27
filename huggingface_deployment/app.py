"""
Afaan Oromo STT API - Hugging Face Spaces Deployment
Production API for Speech-to-Text and Subtitle Generation
"""
from fastapi import FastAPI, File, UploadFile, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, FileResponse, Response
import torch
from transformers import pipeline
import tempfile
import os
import librosa
import numpy as np
import shutil
from datetime import datetime
from pathlib import Path
import asyncio
import json
import base64
from typing import List, Dict

app = FastAPI(
    title="Afaan Oromo STT API",
    version="1.0.0",
    description="Speech-to-Text and Subtitle Generation for Afaan Oromo",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

MODEL_PATH = "HNDE/afaan-oromo-whisper-small"
asr_pipeline = None
TEMP_DIR = Path("/tmp/oromo_stt")
TEMP_DIR.mkdir(exist_ok=True)

CHUNK_LENGTH = 30
BATCH_SIZE = 8
NUM_BEAMS = 5
TEMPERATURE = 0.0
COMPRESSION_RATIO_THRESHOLD = 2.4
LOGPROB_THRESHOLD = -1.0
NO_SPEECH_THRESHOLD = 0.6

MAX_FILE_SIZE_MB = 500
MAX_AUDIO_DURATION_SECONDS = 600
RECOMMENDED_DURATION_SECONDS = 180

@app.on_event("startup")
async def startup_event():
    global asr_pipeline
    device = 0 if torch.cuda.is_available() else -1
    
    print(f"Loading model: {MODEL_PATH}")
    print(f"Device: {'GPU' if device >= 0 else 'CPU'}")
    
    asr_pipeline = pipeline(
        "automatic-speech-recognition",
        model=MODEL_PATH,
        device=device,
        return_timestamps=True,
        chunk_length_s=CHUNK_LENGTH
    )
    print("Model loaded successfully!")
    print(f"Quality settings: beams={NUM_BEAMS}, temp={TEMPERATURE}")

@app.get("/")
async def root():
    return {
        "name": "Afaan Oromo STT API",
        "version": "1.0.0",
        "status": "running",
        "docs": "/docs"
    }

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "model_loaded": asr_pipeline is not None,
        "model": MODEL_PATH,
        "device": "GPU" if torch.cuda.is_available() else "CPU",
        "limits": {
            "max_file_size_mb": MAX_FILE_SIZE_MB,
            "max_duration_minutes": MAX_AUDIO_DURATION_SECONDS // 60,
            "recommended_duration_minutes": RECOMMENDED_DURATION_SECONDS // 60
        },
        "quality_settings": {
            "num_beams": NUM_BEAMS,
            "temperature": TEMPERATURE,
            "compression_ratio_threshold": COMPRESSION_RATIO_THRESHOLD,
            "logprob_threshold": LOGPROB_THRESHOLD,
            "no_speech_threshold": NO_SPEECH_THRESHOLD
        }
    }

def get_audio_duration(file_path):
    """Get audio duration without loading entire file"""
    try:
        duration = librosa.get_duration(path=file_path)
        return duration
    except Exception as e:
        print(f"Error getting duration: {e}")
        return None

def validate_audio_file(file_path):
    """Validate audio file size and duration"""
    file_size = os.path.getsize(file_path)
    if file_size > MAX_FILE_SIZE_MB * 1024 * 1024:
        raise HTTPException(
            status_code=400, 
            detail=f"File too large (max {MAX_FILE_SIZE_MB}MB)"
        )
    
    duration = get_audio_duration(file_path)
    if duration is None:
        raise HTTPException(status_code=400, detail="Invalid audio file")
    
    if duration > MAX_AUDIO_DURATION_SECONDS:
        raise HTTPException(
            status_code=400,
            detail=f"Audio too long (max {MAX_AUDIO_DURATION_SECONDS//60} minutes). Current: {duration//60:.1f} minutes"
        )
    
    return duration

def preprocess_audio(audio, sr=16000):
    audio, _ = librosa.effects.trim(audio, top_db=20)
    rms = np.sqrt(np.mean(audio**2))
    if rms > 1e-3:  # Skip normalization for nearly silent audio
        target_rms = 10**(-20/20)
        audio = audio * (target_rms / rms)
    audio = np.clip(audio, -1.0, 1.0)
    return audio

def process_long_audio_chunked(audio, sr=16000):
    """Process long audio in chunks to avoid timeout"""
    chunk_duration = 60
    chunk_samples = chunk_duration * sr
    
    if len(audio) <= chunk_samples * 2:
        audio = preprocess_audio(audio, sr)
        result = asr_pipeline(
            {"array": audio, "sampling_rate": sr},
            return_timestamps="word",
            chunk_length_s=CHUNK_LENGTH,
            batch_size=BATCH_SIZE,
            generate_kwargs={
                "num_beams": NUM_BEAMS,
                "max_length": 225,
                "temperature": TEMPERATURE,
                "compression_ratio_threshold": COMPRESSION_RATIO_THRESHOLD,
                "logprob_threshold": LOGPROB_THRESHOLD,
                "no_speech_threshold": NO_SPEECH_THRESHOLD,
            }
        )
        return result
    
    all_chunks = []
    for i in range(0, len(audio), chunk_samples):
        chunk = audio[i:i + chunk_samples]
        
        result = asr_pipeline(
            {"array": chunk, "sampling_rate": sr},
            return_timestamps="word",
            chunk_length_s=CHUNK_LENGTH,
            batch_size=BATCH_SIZE,
            generate_kwargs={
                "num_beams": 1,
                "max_length": 225,
                "temperature": TEMPERATURE,
                "compression_ratio_threshold": COMPRESSION_RATIO_THRESHOLD,
                "logprob_threshold": LOGPROB_THRESHOLD,
                "no_speech_threshold": NO_SPEECH_THRESHOLD,
            }
        )
        
        if result.get("chunks"):
            offset = i / sr
            for chunk_data in result["chunks"]:
                if chunk_data.get("timestamp"):
                    timestamp = chunk_data["timestamp"]
                    chunk_data["timestamp"] = [
                        (timestamp[0] or 0) + offset,
                        (timestamp[1] or timestamp[0] or 0) + offset
                    ]
            all_chunks.extend(result["chunks"])
    
    combined_text = " ".join([c.get("text", "") for c in all_chunks if c.get("text")])
    return {
        "text": combined_text,
        "chunks": all_chunks
    }

def clean_text(text):
    if not text:
        return ""
    text = " ".join(text.split())
    if text and text[-1] not in '.!?።':
        text += '.'
    return text

def create_segments_from_chunks(result, max_words_per_segment=10, min_pause_duration=0.3):
    """Create subtitle segments with intelligent pause detection"""
    segments = []
    
    if "chunks" not in result or not result["chunks"]:
        text = result.get("text", "")
        if text.strip():
            words = text.split()
            duration = max(3.0, len(words) / 2.5)
            segments.append({
                "start": float(0.0),
                "end": float(duration),
                "text": str(text)
            })
        return segments
    
    word_chunks = []
    for idx, chunk in enumerate(result["chunks"]):
        try:
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
                "start": float(start),
                "end": float(end),
                "text": str(text)
            })
        except Exception as e:
            print(f"[ERROR] Processing chunk {idx}: {e}, chunk: {chunk}")
            continue
    
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
            segment_text = clean_text(segment_text)
            segment_end = chunk["end"]
            
            if segment_text:
                segments.append({
                    "start": float(round(segment_start, 2)),
                    "end": float(round(segment_end, 2)),
                    "text": str(segment_text)
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
                merged_text = clean_text(merged_text)
                merged.append({
                    "start": float(current["start"]),
                    "end": float(next_seg["end"]),
                    "text": str(merged_text)
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
            seg["end"] = float(seg["start"] + 0.2)
        
        if i < len(segments) - 1:
            next_seg = segments[i + 1]
            if seg["end"] > next_seg["start"]:
                seg["end"] = float(next_seg["start"] - 0.05)
        
        seg["start"] = float(round(seg["start"], 2))
        seg["end"] = float(round(seg["end"], 2))
        seg["text"] = str(seg["text"])
    
    return segments

def format_timestamp_srt(seconds):
    """Convert seconds to SRT timestamp format (HH:MM:SS,mmm)"""
    if seconds is None:
        seconds = 0
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    secs = int(seconds % 60)
    milliseconds = int((seconds - int(seconds)) * 1000)
    return f"{hours:02d}:{minutes:02d}:{secs:02d},{milliseconds:03d}"

def generate_srt_content(subtitles: List[Dict]) -> str:
    """Generate SRT format subtitle content"""
    srt_content = []
    for i, subtitle in enumerate(subtitles, start=1):
        start_time = format_timestamp_srt(subtitle['start'])
        end_time = format_timestamp_srt(subtitle['end'])
        text = subtitle['text'].strip()
        
        srt_content.append(f"{i}")
        srt_content.append(f"{start_time} --> {end_time}")
        srt_content.append(text)
        srt_content.append("")
    
    return "\n".join(srt_content)

def generate_txt_content(subtitles: List[Dict]) -> str:
    """Generate plain text content from subtitles"""
    return "\n".join([subtitle['text'].strip() for subtitle in subtitles if subtitle['text'].strip()])

async def process_audio_chunk(audio_data: bytes, sample_rate: int = 16000):
    """Process audio chunk for streaming transcription"""
    try:
        audio_array = np.frombuffer(audio_data, dtype=np.int16).astype(np.float32) / 32768.0
        
        if len(audio_array) < sample_rate * 0.5:
            return None
        
        audio_array = preprocess_audio(audio_array, sample_rate)
        
        result = asr_pipeline(
            {"array": audio_array, "sampling_rate": sample_rate},
            return_timestamps=False,
            chunk_length_s=CHUNK_LENGTH,
            generate_kwargs={
                "num_beams": 1,
                "max_length": 225,
                "temperature": TEMPERATURE,
            }
        )
        
        text = clean_text(result.get("text", ""))
        return text if text else None
        
    except Exception as e:
        print(f"Error processing audio chunk: {e}")
        return None

@app.post("/transcribe")
async def transcribe_audio(file: UploadFile = File(...)):
    temp_file_path = None
    
    try:
        temp_file_path = TEMP_DIR / f"{datetime.now().timestamp()}_{file.filename}"
        
        with open(temp_file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
        
        duration = validate_audio_file(temp_file_path)
        file_size = os.path.getsize(temp_file_path)
        
        warning = None
        if duration > RECOMMENDED_DURATION_SECONDS:
            warning = f"Audio is {duration//60:.1f} minutes. Processing may take longer and could timeout on free tier."
        
        audio, sr = librosa.load(temp_file_path, sr=16000, mono=True)
        
        result = process_long_audio_chunked(audio, sr)
        
        text = clean_text(result.get("text", ""))
        word_count = len(text.split())
        
        print(f"[DEBUG] Transcription result - text length: {len(text)}, word count: {word_count}")
        
        response_data = {
            "success": True,
            "text": str(text),
            "metadata": {
                "word_count": int(word_count),
                "character_count": int(len(text)),
                "duration": float(round(duration, 2)),
                "file_size": int(file_size),
                "filename": str(file.filename),
                "timestamp": str(datetime.utcnow().isoformat())
            }
        }
        
        if warning:
            response_data["warning"] = str(warning)
        
        print(f"[DEBUG] Response data: {response_data}")
        
        return JSONResponse(response_data)
        
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        error_details = traceback.format_exc()
        print(f"[ERROR] Transcription error: {e}")
        print(f"[ERROR] Traceback:\n{error_details}")
        raise HTTPException(status_code=500, detail=f"Transcription failed: {str(e)}")
    finally:
        if temp_file_path and os.path.exists(temp_file_path):
            try:
                os.remove(temp_file_path)
            except Exception as e:
                print(f"Cleanup error: {e}")

@app.post("/generate-subtitles-json")
async def generate_subtitles_json(file: UploadFile = File(...)):
    """
    Generate subtitles and return as JSON with segments (mobile app format)
    
    Returns:
    - success: bool
    - segments: list of {start, end, text}
    - full_text: complete transcription
    - srt: SRT formatted subtitles
    - metadata: {segment_count, filename, timestamp}
    """
    temp_file_path = None
    
    try:
        temp_file_path = TEMP_DIR / f"{datetime.now().timestamp()}_{file.filename}"
        
        with open(temp_file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
        
        duration = validate_audio_file(temp_file_path)
        
        print(f"[SUBTITLES] Generating for: {file.filename}")
        audio, sr = librosa.load(temp_file_path, sr=16000, mono=True)
        
        result = process_long_audio_chunked(audio, sr)
        print(f"[DEBUG] Result type: {type(result)}, keys: {result.keys() if isinstance(result, dict) else 'N/A'}")
        
        # Create intelligent segments
        segments = create_segments_from_chunks(result)
        print(f"[DEBUG] Segments type: {type(segments)}, length: {len(segments)}")
        if segments:
            print(f"[DEBUG] First segment: {segments[0]}")
        
        # Generate SRT content
        srt_content = generate_srt_content(segments)
        
        # Get full text
        full_text = clean_text(result.get("text", ""))
        
        print(f"[SUCCESS] Generated {len(segments)} subtitle segments")
        
        return JSONResponse({
            "success": True,
            "segments": segments,
            "full_text": full_text,
            "srt": srt_content,
            "metadata": {
                "segment_count": len(segments),
                "filename": file.filename,
                "timestamp": datetime.utcnow().isoformat()
            }
        })
        
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        error_details = traceback.format_exc()
        print(f"[ERROR] Subtitle generation error: {e}")
        print(f"[ERROR] Traceback:\n{error_details}")
        raise HTTPException(status_code=500, detail=f"Subtitle generation failed: {str(e)}")
    finally:
        if temp_file_path and os.path.exists(temp_file_path):
            try:
                os.remove(temp_file_path)
            except Exception as e:
                print(f"Cleanup error: {e}")

@app.post("/generate-subtitles")
async def generate_subtitles_file(file: UploadFile = File(...), format: str = "srt"):
    """Generate subtitle file in SRT or TXT format"""
    temp_file_path = None
    output_file_path = None
    
    try:
        if format.lower() not in ["srt", "txt"]:
            raise HTTPException(status_code=400, detail="Format must be 'srt' or 'txt'")
        
        temp_file_path = TEMP_DIR / f"{datetime.now().timestamp()}_{file.filename}"
        
        with open(temp_file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
        
        duration = validate_audio_file(temp_file_path)
        
        audio, sr = librosa.load(temp_file_path, sr=16000, mono=True)
        
        result = process_long_audio_chunked(audio, sr)
        
        chunks = result.get("chunks", [])
        subtitles = []
        
        for chunk in chunks:
            start = chunk.get("timestamp", [0, 0])[0] or 0
            end = chunk.get("timestamp", [0, 0])[1] or start + 2
            text = chunk.get("text", "").strip()
            
            if text:
                subtitles.append({
                    "start": start,
                    "end": end,
                    "text": text
                })
        
        if not subtitles:
            raise HTTPException(status_code=400, detail="No speech detected in audio")
        
        base_filename = os.path.splitext(file.filename)[0]
        output_filename = f"{base_filename}.{format.lower()}"
        output_file_path = TEMP_DIR / f"{datetime.now().timestamp()}_{output_filename}"
        
        if format.lower() == "srt":
            content = generate_srt_content(subtitles)
            media_type = "application/x-subrip"
        else:
            content = generate_txt_content(subtitles)
            media_type = "text/plain"
        
        with open(output_file_path, "w", encoding="utf-8") as f:
            f.write(content)
        
        return FileResponse(
            path=output_file_path,
            filename=output_filename,
            media_type=media_type,
            background=None
        )
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Subtitle file generation error: {e}")
        raise HTTPException(status_code=500, detail=f"Subtitle generation failed: {str(e)}")
    finally:
        if temp_file_path and os.path.exists(temp_file_path):
            try:
                os.remove(temp_file_path)
            except Exception as e:
                print(f"Cleanup error: {e}")
        if output_file_path and os.path.exists(output_file_path):
            asyncio.create_task(cleanup_file_later(output_file_path, delay=300))

async def cleanup_file_later(file_path, delay: int = 60):
    """Cleanup file after delay to allow download completion"""
    await asyncio.sleep(delay)
    try:
        if os.path.exists(file_path):
            os.remove(file_path)
    except Exception as e:
        print(f"Error cleaning up file {file_path}: {e}")

@app.websocket("/ws/live-transcribe")
async def websocket_live_transcribe(websocket: WebSocket):
    """WebSocket endpoint for live/real-time transcription streaming"""
    await websocket.accept()
    
    audio_buffer = bytearray()
    chunk_size = 16000 * 2
    transcription_history = []
    
    try:
        consecutive_timeouts = 0
        max_timeouts = 6  # 6 * 30s = 3 minutes max idle
        
        await websocket.send_json({
            "type": "connection",
            "status": "connected",
            "message": "Live transcription started"
        })
        
        while True:
            try:
                data = await asyncio.wait_for(websocket.receive(), timeout=30.0)
                
                if data["type"] == "websocket.disconnect":
                    break
                
                if "bytes" in data:
                    consecutive_timeouts = 0
                    audio_chunk = data["bytes"]
                    audio_buffer.extend(audio_chunk)
                    
                    if len(audio_buffer) >= chunk_size:
                        process_chunk = bytes(audio_buffer[:chunk_size])
                        audio_buffer = audio_buffer[chunk_size:]
                        
                        text = await process_audio_chunk(process_chunk)
                        
                        if text and text not in transcription_history[-3:]:
                            transcription_history.append(text)
                            
                            await websocket.send_json({
                                "type": "transcription",
                                "text": text,
                                "timestamp": datetime.utcnow().isoformat(),
                                "is_final": False
                            })
                
                elif "text" in data:
                    message = json.loads(data["text"]) if isinstance(data["text"], str) else data["text"]
                    
                    if message.get("action") == "finish":
                        if len(audio_buffer) > 0:
                            text = await process_audio_chunk(bytes(audio_buffer))
                            if text:
                                transcription_history.append(text)
                                await websocket.send_json({
                                    "type": "transcription",
                                    "text": text,
                                    "timestamp": datetime.utcnow().isoformat(),
                                    "is_final": True
                                })
                        
                        await websocket.send_json({
                            "type": "complete",
                            "full_transcription": " ".join(transcription_history),
                            "message": "Transcription completed"
                        })
                        break
                        
            except asyncio.TimeoutError:
                consecutive_timeouts += 1
                if consecutive_timeouts >= max_timeouts:
                    await websocket.send_json({
                        "type": "timeout",
                        "message": "Connection timed out due to inactivity"
                    })
                    break
                await websocket.send_json({
                    "type": "ping",
                    "message": "Keep-alive ping"
                })
                continue
                
    except WebSocketDisconnect:
        print("WebSocket disconnected")
    except Exception as e:
        print(f"WebSocket error: {e}")
        try:
            await websocket.send_json({
                "type": "error",
                "message": str(e)
            })
        except:
            pass
    finally:
        try:
            await websocket.close()
        except:
            pass

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=7860)
