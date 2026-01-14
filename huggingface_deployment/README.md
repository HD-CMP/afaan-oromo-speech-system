---
title: Afaan Oromo STT API
emoji: 🎙️
colorFrom: blue
colorTo: green
sdk: docker
pinned: false
license: mit
---

# Afaan Oromo Speech-to-Text API

An AI-powered Speech-to-Text system for the Afaan Oromo language, developed as part of a research project at Ethiopian universities.

## Features

- **Speech-to-Text Transcription**: Convert Afaan Oromo audio to text
- **Subtitle Generation**: Automatic .srt and .txt subtitle creation
- **Real-time Processing**: Fast inference using Whisper model
- **Chunked Processing**: Handles long audio files up to 10 minutes
- **Live Transcription**: WebSocket streaming for real-time transcription
- **Mobile-Ready**: RESTful API for Android/iOS apps

## Audio Limits

| Limit | Value | Note |
|-------|-------|------|
| **Max File Size** | 500 MB | Hard limit |
| **Max Duration** | 10 minutes | Hard limit to prevent timeouts |
| **Recommended Duration** | 3 minutes | Optimal for free tier performance |

**Note:** Files longer than 3 minutes are processed in 60-second chunks to avoid HuggingFace free tier timeouts.

## API Endpoints

### `GET /`
Root endpoint - API information

### `GET /health`
Health check endpoint

### `POST /transcribe`
Transcribe audio file to text
- **Input**: Audio file (multipart/form-data)
- **Output**: JSON with transcribed text and metadata

### `POST /generate-subtitles-json`
Generate subtitles from audio (JSON format)
- **Input**: Audio file (multipart/form-data)
- **Output**: JSON with timestamped subtitle chunks

### `POST /generate-subtitles`
Generate subtitle file in SRT or TXT format
- **Input**: 
  - Audio file (multipart/form-data)
  - `format` parameter: "srt" or "txt" (default: "srt")
- **Output**: Downloadable .srt or .txt file

### `WebSocket /ws/live-transcribe`
Live/real-time transcription streaming
- **Protocol**: WebSocket
- **Input**: Audio chunks (binary data, 16kHz PCM)
- **Output**: Real-time transcription results (JSON messages)
- **Features**: 
  - Word-by-word streaming
  - Keep-alive pings
  - Complete transcription on finish

## Usage Examples

### Transcribe Audio
```python
import requests

url = "https://YOUR-SPACE-NAME.hf.space/transcribe"
files = {"file": open("audio.wav", "rb")}
response = requests.post(url, files=files)
print(response.json())
```

### Generate SRT Subtitle File
```python
import requests

url = "https://YOUR-SPACE-NAME.hf.space/generate-subtitles"
files = {"file": open("audio.wav", "rb")}
data = {"format": "srt"}
response = requests.post(url, files=files, data=data)

with open("output.srt", "wb") as f:
    f.write(response.content)
```

### Live Transcription (WebSocket)
```python
import asyncio
import websockets
import wave

async def live_transcribe():
    uri = "wss://YOUR-SPACE-NAME.hf.space/ws/live-transcribe"
    
    async with websockets.connect(uri) as websocket:
        # Wait for connection message
        connection_msg = await websocket.recv()
        print(connection_msg)
        
        # Send audio chunks
        with wave.open("audio.wav", "rb") as wav:
            while True:
                audio_chunk = wav.readframes(16000)
                if not audio_chunk:
                    break
                await websocket.send(audio_chunk)
                
                # Receive transcription
                response = await websocket.recv()
                print(response)
        
        # Finish
        await websocket.send('{"action": "finish"}')
        final_msg = await websocket.recv()
        print(final_msg)

asyncio.run(live_transcribe())
```

## Troubleshooting

### Space Sleeps After Inactivity
**Issue:** First request after 48 hours takes 30-60 seconds  
**Solution:** Mobile app automatically handles wake-up with extended timeout

### Timeout with Long Audio
**Issue:** Processing fails or disconnects with long files  
**Solution:** 
- Keep audio under 3 minutes for best results
- API automatically chunks longer files (up to 10 minutes)
- Files over 10 minutes are rejected

### Connection Refused
**Issue:** Cannot connect to API  
**Solution:**
- Check if Space is awake: visit `/health` endpoint
- Wait 60 seconds for Space to wake up
- Retry request

### Slow Processing
**Issue:** Transcription takes too long  
**Solution:**
- Free tier uses CPU (slower)
- Consider upgrading to GPU tier ($0.60/hour)
- Reduce audio file size/duration

## Technology Stack

- **Model**: OpenAI Whisper (fine-tuned for Afaan Oromo)
- **Framework**: FastAPI
- **Deployment**: Hugging Face Spaces

## Project Information

This API is part of an academic research project focused on developing AI-powered language technology for low-resource African languages, specifically Afaan Oromo.

**Supported by**:
- Hugging Face
- Masakhane NLP
- AI4D Africa Initiative

## License

MIT License - Open source for educational and research purposes
