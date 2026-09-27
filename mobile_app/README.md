# Afaan Oromo STT - Mobile Application

Android application for Afaan Oromo speech-to-text transcription and subtitle generation with semi-offline capability.

---

## Features

**API-Based Transcription**: Cloud processing via FastAPI backend  
**Instant Mode**: Upload or record audio for transcription  
**Live Mode**: Real-time file-based transcription with history  
**Subtitle Generation**: Synchronized .srt and .txt subtitle files  
**Semi-Offline Queue**: Request queuing system for low-connectivity environments

---

## Quick Start

### Prerequisites

- Flutter SDK 3.0+
- Android Studio
- Android device (API 24+) or emulator
- Backend API running (see parent README.md)

### Setup

```bash
cd mobile_app
flutter pub get
flutter run
```

### Build Release APK

```bash
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

---

## Architecture

### API-Based Processing

The mobile app communicates with the FastAPI backend for all transcription processing.

**Request Flow**:
1. User selects audio file
2. App checks internet connection
3. **Online**: Upload to API, process, display result
4. **Offline**: Queue request locally for later processing
5. **Auto-sync**: Queue processes automatically when connection restored

**Benefits**:
- Consistent transcription quality
- No device storage constraints
- Centralized model updates
- Works on low-end devices

---

## Project Structure

```
mobile_app/
├── lib/
│   ├── main.dart
│   ├── services/
│   │   ├── api_service.dart             # API client
│   │   ├── history_service.dart         # Local history
│   │   └── export_service.dart          # File export
│   ├── providers/
│   │   ├── transcription_provider.dart  # Queue management
│   │   └── subtitle_provider.dart
│   ├── screens/
│   │   ├── home_screen.dart
│   │   ├── transcription_screen.dart    # Instant Mode
│   │   ├── live_transcription_screen.dart  # Live Mode
│   │   └── subtitle_screen.dart
│   └── models/
│       ├── transcription_result.dart
│       └── subtitle_result.dart
├── assets/
│   ├── images/                          # App assets
│   └── icons/
├── android/                             # Android platform
└── pubspec.yaml                         # Dependencies
```

---

## Dependencies

**Core**:
- flutter (SDK)
- provider (State management)

**File Handling**:
- file_picker
- path_provider
- permission_handler

**Networking**:
- http (API client)
- dio (Advanced HTTP)

**Local Storage**:
- shared_preferences (Queue persistence)

**Export**:
- share_plus

See `pubspec.yaml` for complete list.

---

## Usage

### 1. Transcription (Instant Mode)

1. Open app → Transcription screen
2. Tap "Pick Audio File"
3. Select audio file (MP3, WAV, M4A, etc.)
4. Wait for processing
5. View transcription, copy, or export

**If offline**: File is queued and will process when connection is restored.

### 2. Live Transcription

1. Navigate to Live Transcription screen
2. Record audio or upload file
3. View real-time transcription
4. Save to history

### 3. Subtitle Generation

1. Navigate to Subtitle Generation screen
2. Upload audio or video file
3. Wait for processing
4. View timestamped segments
5. Export as .srt or .txt

---

## Semi-Offline Functionality

### How It Works

The app implements a **request queuing system** as specified in the project proposal:

**Online Mode**:
- Direct communication with API
- Immediate transcription results
- Real-time progress updates

**Offline Mode**:
- Audio files are queued locally
- Queue persists across app restarts
- User can continue selecting files

**Auto-Sync**:
- App periodically checks connectivity
- Queued requests process automatically
- User receives notification when complete

### Queue Management

View queued requests in the app:
- **Queue screen**: Shows pending requests
- **Auto-retry**: Failed requests retry automatically
- **Manual clear**: User can remove items from queue

---

## Configuration

### API Endpoint

Edit `lib/services/api_service.dart`:

```dart
class ApiService {
  // For Android emulator
  static const String baseUrl = 'http://10.0.2.2:8000';
  
  // For physical device (replace with your IP)
  // static const String baseUrl = 'http://192.168.1.X:8000';
}
```

**Finding your IP**:
```bash
# Windows
ipconfig

# Linux/Mac
ifconfig
```

---

## Testing

### Local Testing

```bash
flutter run --debug
```

**Test checklist**:
- [ ] Audio file upload (various formats)
- [ ] API connection
- [ ] Transcription accuracy
- [ ] Subtitle generation
- [ ] Export functionality
- [ ] History persistence
- [ ] Queue system (offline mode)
- [ ] Auto-sync when reconnected

### Build Testing

```bash
flutter build apk --release
adb install build/app/outputs/flutter-apk/app-release.apk
```

---

## Deployment

### Direct APK Distribution

```bash
flutter build apk --release
```

Share APK file for direct installation.

### Google Play Store

```bash
flutter build appbundle --release
```

Upload `.aab` file to Play Console.

**Store listing**:
- **Title**: Afaan Oromo STT
- **Category**: Productivity
- **Description**: Cloud-based Oromo speech-to-text transcription with offline queue
- **Keywords**: Oromo, speech-to-text, transcription, subtitle

See parent `docs/DEPLOYMENT_GUIDE.md` for complete deployment instructions.

---

## Troubleshooting

### Problem: Cannot connect to API

**Solution**:
- Verify backend is running: `curl http://localhost:8000/health`
- Check IP address in `api_service.dart`
- Ensure device and server on same network (for physical device)
- Disable firewall on port 8000
- For emulator, use `http://10.0.2.2:8000`

### Problem: Files not uploading

**Solution**:
- Check file size (max 500 MB by default)
- Verify supported formats: MP3, WAV, M4A, FLAC, OGG
- Check storage permissions
- View queue screen to see if request was queued

### Problem: Queue not processing

**Solution**:
- Verify internet connection
- Check backend API status
- Clear and re-add item to queue
- Restart app to reload queue

### Problem: Build failed

**Solution**:
```bash
flutter clean
flutter pub cache repair
flutter pub get
flutter build apk --release
```

---

## Development

### Adding New Features

1. Create UI in `lib/screens/`
2. Add business logic in `lib/providers/`
3. Update navigation in `lib/main.dart`
4. Test with `flutter run --debug`

### Modifying Queue System

Queue logic is in `lib/providers/transcription_provider.dart`:
- `_addToQueue()`: Add request to queue
- `_processQueue()`: Process queued requests
- `_loadQueuedRequests()`: Load queue on startup
- `_saveQueuedRequests()`: Persist queue to storage

---

## Permissions

Required Android permissions (auto-configured):

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

---

## Performance

### System Requirements

- Android 7.0 (API 24) or higher
- ARM or ARM64 architecture
- 1 GB RAM minimum
- Internet connection (required for processing, queue available for offline)

### Expected Performance

| Metric | Value |
|--------|-------|
| App size | ~20 MB (no models) |
| Upload time | Depends on file size & network |
| Processing time | 2-5 seconds (30-sec audio, server-side) |
| Queue capacity | Limited by device storage |

---

## License

Part of Afaan Oromo STT project. Open-source for educational use.

---

## Support

**Setup Issues**: See parent `README.md` and `docs/SETUP_GUIDE.md`  
**Deployment**: See `docs/DEPLOYMENT_GUIDE.md`  
**API Reference**: See `docs/API_DOCUMENTATION.md`

---

**Built with Flutter for the Oromo-speaking community**
