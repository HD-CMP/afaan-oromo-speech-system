FROM python:3.10-slim

WORKDIR /app

# Install system dependencies for audio processing
RUN apt-get update && apt-get install -y \
    ffmpeg \
    libsndfile1 \
    git \
    && rm -rf /var/lib/apt/lists/*

# Copy deployment app
COPY huggingface_deployment/app.py .

# Install Python dependencies
RUN pip install --no-cache-dir \
    fastapi==0.104.1 \
    uvicorn[standard]==0.24.0 \
    transformers==4.35.2 \
    torch==2.1.0 \
    torchaudio==2.1.0 \
    librosa==0.10.1 \
    soundfile==0.12.1 \
    numpy==1.24.4 \
    python-multipart==0.0.6 \
    accelerate==0.24.1

# HuggingFace Spaces runs on port 7860
EXPOSE 7860

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "7860"]
