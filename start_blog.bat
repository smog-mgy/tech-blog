@echo off
cd /d D:\Pythonproject\tech-blog
start "Blog Server" /min cmd /k "F:\develop\Anaconda3\envs\blog_env\Scripts\mkdocs.exe serve -a 127.0.0.1:8000"
timeout /t 8 /nobreak >nul
start http://127.0.0.1:8000
