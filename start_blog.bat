@echo off
setlocal
cd /d "%~dp0"
set "PYTHONIOENCODING=utf-8"
echo Blog preview: http://127.0.0.1:8000
echo Keep this window open while using the preview.
"F:\develop\Anaconda3\envs\blog_env\python.exe" -m mkdocs serve -a 127.0.0.1:8000
pause
