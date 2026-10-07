for start the flutte project

Setup A: USB cable with adb reverse (daily development)

Terminal 1: backend

powershell
cd path\to\backend
uvicorn main:app --host 127.0.0.1 --port 8000 --reload

Terminal 2: tunnel and app

powershell
adb devices                         # phone must show "device"
adb reverse tcp:8000 tcp:8000       # create the tunnel
adb reverse --list                  # should print tcp:8000 tcp:8000
cd path\to\client\chat_app
flutter run

Constants

dart
static const String baseUrl = 'http://127.0.0.1:8000';
static const String wsUrl = 'ws://127.0.0.1:8000';

Rerun adb reverse tcp:8000 tcp:8000 whenever you:

unplug and replug the cable
reboot the phone
restart adb (adb kill-server)
see connection timeouts again



Setup B: Wi-Fi without cable (normal network)

Phone and laptop must be on the same Wi-Fi, with no adb reverse needed.

Terminal 1: backend

powershell
cd path\to\backend
uvicorn main:app --host 0.0.0.0 --port 8000 --reload

Find the laptop's IP

powershell
ipconfig                            # copy IPv4 Address of the Wi-Fi adapter

Constants (use that IP in both lines)

dart
static const String baseUrl = 'http://192.168.x.x:8000';
static const String wsUrl = 'ws://192.168.x.x:8000';

Terminal 2: app

powershell
cd path\to\client\chat_app
flutter run

Checks for Wi-Fi mode

Test http://192.168.x.x:8000/docs in the phone's Chrome first.
