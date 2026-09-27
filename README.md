# Development of an Integrated Speech Technology System for Afaan Oromo

<p align="center">
  <img src="https://img.shields.io/badge/Language-Afaan%20Oromoo-blue?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/WER-1.5%25-brightgreen?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/MOS-4.35%2F5-gold?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/License-Open%20Access-green?style=for-the-badge"/>
</p>

> **Bachelor of Science Thesis** — Hawassa University, Hawassa Institute of Technology  
> Department of Electrical and Computer Engineering (Computer Engineering Stream)  
> **Authors**: Admassu Ashebir · Hunde Dejene · Nimona Asefa  
> **Advisor**: Mr. Musa Hayato (MSc) · **Submitted**: May 2026

---

## 📄 Read the Paper

| Format | Link |
|--------|------|
| 📥 **Full Thesis PDF** | [Download PDF](paper/Afaan_Oromoo_Speech_Thesis_Final.pdf) |
| 🤗 **Live Demo** | [Hugging Face Space](https://huggingface.co/spaces/HNDE/afaan-oromo-stt-api) |
| 📱 **Mobile App** | [Download APK](https://github.com/HD-CMP/afaan-oromo-speech-system/releases) |

### Cite This Work

**APA:**
> Ashebir, A., Dejene, H., & Asefa, N. (2026). *Development of an Integrated Speech Technology System for Afaan Oromo* [Bachelor's thesis]. Hawassa University, Hawassa Institute of Technology.

**BibTeX:**
```bibtex
@thesis{ashebir2026afaan,
  title={Development of an Integrated Speech Technology System for Afaan Oromo},
  author={Ashebir, Admassu and Dejene, Hunde and Asefa, Nimona},
  year={2026},
  month={May},
  school={Hawassa University, Hawassa Institute of Technology},
  address={Hawassa, Ethiopia},
  type={Bachelor's Thesis},
  department={Department of Electrical and Computer Engineering}
}
```

---

## Abstract

Cushitic languages such as Afaan Oromo spoken by over 50 million people in the Horn of Africa remain critically underrepresented in speech technology. This thesis addresses this gap through a comparative empirical evaluation of three neural TTS architectures — **F5-TTS**, **VITS**, and **Fish Speech** — across ten experimental configurations.

**Key Findings:**
- Fish Speech fine-tuned via **LoRA (r=32) + RVC v2** achieves the highest naturalness/intelligibility: **MOS = 4.35** (10 native speakers)
- Whisper-Small ASR fine-tuned on **101,518 pairs (~141 hours)** achieves **WER = 1.5%**
- Architecture selection is more consequential than dataset scale for low-resource TTS
- System deployed to **4 Hugging Face Spaces** with FastAPI backend + Flutter mobile app

**Keywords:** Afaan Oromoo · Speech Recognition · Text-to-Speech · VITS · Fish Speech · LoRA · Whisper · Low-Resource NLP

---

## Project Overview

**Institution**: Hawassa University — Hawassa Institute of Technology  
**Timeline**: January 2026 – May 2026

## Statement of the Problem

Most existing speech recognition systems (Google Recorder, Otter.ai) are optimized for high-resource languages like English, Mandarin, and French. Despite being spoken by over 50 million people, Afaan Oromo remains underrepresented in AI-based transcription systems. This gap creates significant challenges:

- **Limited Access**: Oromo speakers face barriers in using voice-driven technologies
- **Content Creation Gap**: Educators and content creators cannot easily generate Oromo subtitles for digital media
- **Accessibility Issues**: Hearing-impaired individuals lack localized captioning tools
- **Digital Preservation**: Risk of language erosion in the digital ecosystem

This project addresses these challenges by developing a localized, open, and accurate STT solution tailored specifically for Afaan Oromo.

---

## Objectives

### General Objective

To design and develop an AI-based Android application capable of performing speech-to-text transcription and subtitle generation for the Afaan Oromo language, utilizing a Web Application as an initial development prototype for early testing and validation.

### Specific Objectives

1. Develop a speech-to-text engine for Afaan Oromo using pre-trained models (Whisper/Wav2Vec2)
2. Create a responsive web interface prototype supporting both real-time (live) and post-recording (instant) transcription modes
3. Implement a subtitle generation module producing synchronized .srt and .txt files from audio/video inputs
4. Evaluate transcription accuracy using Word Error Rate (WER) and subtitle synchronization metrics
5. Ensure secure and privacy-respecting data handling where audio/video files are processed but not permanently stored
6. Explore semi-offline functionality for low-connectivity users (request queuing system)

---

## Features

### Speech-to-Text Modes

**Instant Mode**: Upload or record audio files for transcription after completion  
**Live Mode**: Real-time transcription during speech (file-based processing)

### Subtitle Generation

Upload audio or video files to generate synchronized subtitles in:
- `.srt` format (SubRip with timestamps)
- `.txt` format (plain text transcription)

### Platform Support

**Web Application**: Browser-based prototype using Gradio  
**Mobile Application**: Android app with API integration and semi-offline capability  
**Backend API**: Production FastAPI server with database persistence

---

## Architecture

### System Components

```
┌─────────────────────────────────────────────────────────────┐
│                        Client Layer                          │
│  ┌──────────────────┐              ┌──────────────────┐    │
│  │   Web Prototype  │              │   Mobile App     │    │
│  │    (Gradio UI)   │              │  (Flutter API)   │    │
│  └──────────────────┘              └──────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                      Backend Layer                           │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              FastAPI Server (Python)                  │  │
│  │  • REST API endpoints (/transcribe, /subtitles)      │  │
│  │  • Health monitoring & metrics                        │  │
│  │  • Database persistence (SQLite)                      │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                       AI Engine                              │
│  ┌────────────────────┐                                     │
│  │ Backend Processing │                                     │
│  │ Whisper (FP16)     │                                     │
│  │ PyTorch Model      │                                     │
│  └────────────────────┘                                     │
└─────────────────────────────────────────────────────────────┘
```

### Model Details

**Base Model**: OpenAI Whisper Medium (fine-tuned for Afaan Oromo)

**Training Datasets** (as specified in proposal):
1. **Sagalee ASR Dataset**: 100 hours of read speech from 283 speakers
2. **Jimma University Corpus**: 8,729 utterances from 100 speakers, totaling 18.04 hours
3. **Afaan Oromoo TTS Synthesis Dataset**: 8,076 short audio clips (17 hours)

**Performance Targets**:
- **WER on clean audio**: Target ≤25%
- **WER on noisy audio**: Target ≤35%
- **Processing time**: 2-5 seconds per 30-second audio
- **Subtitle synchronization**: Accurate timestamp-based .srt generation

---

## Quick Start

### Prerequisites

- Python 3.11+
- CUDA-compatible GPU (recommended) or CPU
- Flutter SDK 3.0+ (for mobile app development)
- 2 GB free disk space (for models)

### Backend Setup

```bash
# 1. Clone and navigate to project
cd oromo_asr_backend

# 2. Create virtual environment
python -m venv venv
venv\Scripts\activate  # Windows
source venv/bin/activate  # Linux/Mac

# 3. Install dependencies
pip install -r requirements.txt

# 4. Configure environment
cp .env.example .env
# Edit .env with your settings

# 5. Initialize database
python scripts/maintenance.py init-db

# 6. Start production API
python src/api_production.py
```

API available at: `http://localhost:8000`  
API documentation: `http://localhost:8000/docs`

### Web Prototype

```bash
cd src
python web_prototype.py
```

Access at: `http://localhost:7860`

### Mobile App

```bash
cd mobile_app
flutter pub get
flutter run
```

See `mobile_app/README.md` for detailed setup.

---

## API Usage

### Transcription Endpoint

```bash
POST /transcribe
Content-Type: multipart/form-data

file: <audio_file>
language: "orm"  # Afaan Oromo
task: "transcribe"
```

**Response**:
```json
{
  "transcription": "Translated text in Afaan Oromo",
  "processing_time": 3.45,
  "file_size": 1048576,
  "duration": 30.5
}
```

### Subtitle Generation

```bash
POST /generate-subtitles
Content-Type: multipart/form-data

file: <audio_or_video_file>
output_format: "srt"  # or "txt"
```

**Response**:
```json
{
  "subtitle_file": "subtitles.srt",
  "segments": [
    {
      "start": 0.0,
      "end": 3.5,
      "text": "First subtitle segment"
    }
  ]
}
```

### Health Check

```bash
GET /health/detailed
```

**Response**:
```json
{
  "status": "healthy",
  "model_loaded": true,
  "database_connected": true,
  "disk_space_gb": 45.2,
  "memory_usage_percent": 68.5
}
```

Full API documentation: `docs/API_DOCUMENTATION.md`

---

## Project Structure

```
oromo_asr_backend/
├── src/                          # Source code
│   ├── api_production.py         # Production FastAPI server
│   ├── api.py                    # Development API
│   ├── web_prototype.py          # Gradio web interface
│   ├── config.py                 # Configuration management
│   ├── database.py               # SQLite persistence layer
│   ├── monitoring.py             # Health & metrics monitoring
│   ├── evaluate.py               # Model evaluation (WER)
│   └── utils/
│       └── get_ip.py             # Network utilities
├── models/                       # AI models
│   └── whisper_backend/          # Backend PyTorch model
├── mobile_app/                   # Flutter Android application
│   ├── lib/
│   │   ├── services/             # API client
│   │   ├── providers/            # State management
│   │   ├── screens/              # UI screens
│   │   └── widgets/              # Reusable components
│   └── android/                  # Android platform configuration
├── scripts/                      # Automation scripts
│   ├── backup.py                 # Automated database backups
│   └── maintenance.py            # System maintenance tasks
├── docs/                         # Documentation
│   └── API_DOCUMENTATION.md      # Complete API reference
├── data/                         # Database storage (gitignored)
├── logs/                         # Application logs
├── results/                      # Evaluation results
├── requirements.txt              # Python dependencies
├── .env.example                  # Environment configuration template
├── Dockerfile                    # Container image definition
├── docker-compose.yml            # Docker orchestration
├── setup_production.bat          # One-click production setup
└── start_production.bat          # One-click API startup
```

---

## Evaluation

### Running Model Evaluation

```bash
cd src
python evaluate.py
```

**Metrics Calculated**:
- Word Error Rate (WER)
- Character Error Rate (CER)
- Real-Time Factor (RTF)
- Inference latency

Results saved to: `results/evaluation_results.json`

### Target Performance

| Metric | Target |
|--------|--------|
| WER (clean audio) | ≤ 25% |
| WER (noisy audio) | ≤ 35% |
| Processing time | 2-5 sec (30-sec audio) |

---

## Deployment

### Production Backend

**Option 1: Automated Setup (Windows)**
```bash
setup_production.bat      # First time only
start_production.bat      # Daily startup
```

**Option 2: Docker**
```bash
docker-compose up -d
```

**Option 3: Manual**
```bash
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python src/api_production.py
```

### Mobile App Deployment

**APK Build (Direct Distribution)**
```bash
cd mobile_app
flutter build apk --release
```
Output: `build/app/outputs/flutter-apk/app-release.apk`

**App Bundle (Google Play Store)**
```bash
flutter build appbundle --release
```
Output: `build/app/outputs/bundle/release/app-release.aab`

---

## Configuration

### Environment Variables

Copy `.env.example` to `.env` and configure:

```ini
# Server Configuration
HOST=0.0.0.0
PORT=8000
DEBUG=false

# Model Configuration
MODEL_PATH=models/whisper_backend
DEVICE=auto  # auto, cpu, cuda
BATCH_SIZE=16

# File Limits
MAX_FILE_SIZE_MB=500
MAX_AUDIO_DURATION_MINUTES=120

# Database
DATABASE_URL=sqlite:///data/oromo_stt.db
ENABLE_DATABASE=true

# Rate Limiting
MAX_REQUESTS_PER_MINUTE=10
MAX_CONCURRENT_TRANSCRIPTIONS=3

# Logging
LOG_LEVEL=INFO
LOG_FILE=logs/api.log
```

---

## Mobile App Features

### Semi-Offline Capability

The mobile app implements a **request queuing system** for semi-offline functionality:

- **Online Mode**: Direct API communication for transcription
- **Offline Mode**: Audio files are queued locally
- **Auto-Sync**: Queue automatically processes when connection is restored

This approach ensures users can continue working in low-connectivity environments as specified in the project proposal.

---

## Development Timeline

| Week | Phase | Activities |
|------|-------|-----------|
| 1-2 | Research & Data Acquisition | Dataset preparation, literature review |
| 3-4 | AI Core Development | Model fine-tuning, WER baseline |
| 5-6 | Backend Engineering | FastAPI server, REST endpoints |
| 7 | Optimization & Protocol | Model optimization |
| 8 | Web Prototype | Gradio interface |
| 9 | Mobile UI | Flutter screens, navigation |
| 10 | Mobile Integration | API integration, queue system |
| 11 | Testing & Evaluation | WER evaluation, bug fixes |
| 12 | Finalization | Documentation, submission |

**Current Status**: Week 10 - Mobile Integration & Testing

---

## License

Part of Afaan Oromo STT academic research project. Open-source for educational use.

---

## Support

**Setup Issues**: See `docs/SETUP_GUIDE.md`  
**API Reference**: See `docs/API_DOCUMENTATION.md`  
**Deployment**: See `docs/DEPLOYMENT_GUIDE.md`

---

**Built for the Oromo-speaking community**


