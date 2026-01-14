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
        "quality_settings": {
            "num_beams": NUM_BEAMS,
            "temperature": TEMPERATURE,
            "compression_ratio_threshold": COMPRESSION_RATIO_THRESHOLD,
            "logprob_threshold": LOGPROB_THRESHOLD,
            "no_speech_threshold": NO_SPEECH_THRESHOLD
        }
    }

def preprocess_audio(audio, sr=16000):
    audio, _ = librosa.effects.trim(audio, top_db=20)
    rms = np.sqrt(np.mean(audio**2))
    if rms > 0:
        target_rms = 10**(-20/20)
        audio = audio * (target_rms / rms)
    audio = np.clip(audio, -1.0, 1.0)
    return audio

def clean_text(text):
    if not text:
        return ""
    text = " ".join(text.split())
    if text and text[-1] not in '.!?።':
        text += '.'
    return text

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
                "task": "transcribe",
                "language": None,
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
        
        file_size = os.path.getsize(temp_file_path)
        if file_size > 500 * 1024 * 1024:
            raise HTTPException(status_code=400, detail="File too large (max 500MB)")
        
        audio, sr = librosa.load(temp_file_path, sr=16000, mono=True)
        audio = preprocess_audio(audio)
        
        result = asr_pipeline(
            {"array": audio, "sampling_rate": sr},
            return_timestamps="word",
            chunk_length_s=CHUNK_LENGTH,
            batch_size=BATCH_SIZE,
            generate_kwargs={
                "task": "transcribe",
                "language": None,
                "return_timestamps": True,
                "num_beams": NUM_BEAMS,
                "max_length": 225,
                "temperature": TEMPERATURE,
                "compression_ratio_threshold": COMPRESSION_RATIO_THRESHOLD,
                "logprob_threshold": LOGPROB_THRESHOLD,
                "no_speech_threshold": NO_SPEECH_THRESHOLD,
            }
        )
        
        text = clean_text(result.get("text", ""))
        word_count = len(text.split())
        
        return {
            "text": text,
            "word_count": word_count,
            "character_count": len(text),
            "metadata": {
                "duration": round(len(audio) / sr, 2),
                "size": file_size
            }
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if temp_file_path and os.path.exists(temp_file_path):
            os.remove(temp_file_path)

@app.post("/generate-subtitles-json")
async def generate_subtitles_json(file: UploadFile = File(...)):
    temp_file_path = None
    
    try:
        temp_file_path = TEMP_DIR / f"{datetime.now().timestamp()}_{file.filename}"
        
        with open(temp_file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
        
        audio, sr = librosa.load(temp_file_path, sr=16000, mono=True)
        audio = preprocess_audio(audio)
        
        result = asr_pipeline(
            {"array": audio, "sampling_rate": sr},
            return_timestamps="word",
            chunk_length_s=CHUNK_LENGTH,
            batch_size=BATCH_SIZE,
            generate_kwargs={
                "task": "transcribe",
                "language": None,
                "return_timestamps": True,
                "num_beams": NUM_BEAMS,
                "max_length": 225,
                "temperature": TEMPERATURE,
                "compression_ratio_threshold": COMPRESSION_RATIO_THRESHOLD,
                "logprob_threshold": LOGPROB_THRESHOLD,
                "no_speech_threshold": NO_SPEECH_THRESHOLD,
            }
        )
        
        chunks = result.get("chunks", [])
        subtitles = []
        
        for i, chunk in enumerate(chunks):
            start = chunk.get("timestamp", [0, 0])[0] or 0
            end = chunk.get("timestamp", [0, 0])[1] or start + 2
            text = chunk.get("text", "").strip()
            
            if text:
                subtitles.append({
                    "index": i + 1,
                    "start": start,
                    "end": end,
                    "text": text
                })
        
        return {
            "subtitles": subtitles,
            "total_chunks": len(subtitles)
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if temp_file_path and os.path.exists(temp_file_path):
            os.remove(temp_file_path)

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
        
        audio, sr = librosa.load(temp_file_path, sr=16000, mono=True)
        audio = preprocess_audio(audio)
        
        result = asr_pipeline(
            {"array": audio, "sampling_rate": sr},
            return_timestamps="word",
            chunk_length_s=CHUNK_LENGTH,
            batch_size=BATCH_SIZE,
            generate_kwargs={
                "task": "transcribe",
                "language": None,
                "return_timestamps": True,
                "num_beams": NUM_BEAMS,
                "max_length": 225,
                "temperature": TEMPERATURE,
                "compression_ratio_threshold": COMPRESSION_RATIO_THRESHOLD,
                "logprob_threshold": LOGPROB_THRESHOLD,
                "no_speech_threshold": NO_SPEECH_THRESHOLD,
            }
        )
        
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
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if temp_file_path and os.path.exists(temp_file_path):
            os.remove(temp_file_path)
        if output_file_path and os.path.exists(output_file_path):
            asyncio.create_task(cleanup_file_later(output_file_path, delay=60))

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
