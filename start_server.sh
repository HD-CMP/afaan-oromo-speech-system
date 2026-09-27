#!/bin/bash

echo "========================================"
echo "Oromo ASR Backend Server"
echo "========================================"
echo ""
echo "Starting server control interface..."
echo "Control Port: 8001"
echo "API Port: 8000"
echo ""
echo "Press Ctrl+C to stop"
echo "========================================"
echo ""

python3 server_control.py
