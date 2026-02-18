# Flint Studio (Build Branch)

This branch is for running a prebuilt Flint Studio package.

## 1) Clone the build branch

```bash
git clone -b build https://github.com/flint-dart/flint_studio.git
cd flint_studio/flint_studio/build
```

## 2) Configure `.env`

Create or edit `.env` in this `build/` folder and set login credentials:

```env
FLINT_STUDIO_USERNAME=admin
FLINT_STUDIO_PASSWORD=change_this_password
FLINT_STUDIO_PROFILE_KEY=change_this_profile_key
```

Required:
- `FLINT_STUDIO_USERNAME`
- `FLINT_STUDIO_PASSWORD`

Recommended:
- `FLINT_STUDIO_PROFILE_KEY` (encrypts saved DB profile passwords)

## 3) Start app

Windows:
```bat
start.bat
```

Linux:
```bash
chmod +x start.sh
./start.sh
```

Flint Studio runs on:
- `http://localhost:4033`

## Notes

- Keep `.env` private.
- You can connect to MySQL/PostgreSQL from the UI after login.
- Saved profile data is under `storage/connection_profiles.json`.
