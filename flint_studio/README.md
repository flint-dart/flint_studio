# Flint Studio

## Start (Windows + Linux)

Interactive setup + start:

```bash
dart run bin/start.dart
```

What it does:
- asks if you want MySQL or PostgreSQL
- attempts to install selected database if missing
- runs `dart pub get`
- starts Flint Studio on `http://localhost:4033`

## Build executable

```bash
dart run bin/build.dart
```

Output:
- Windows: `build/flint_studio.exe`
- Linux: `build/flint_studio`
