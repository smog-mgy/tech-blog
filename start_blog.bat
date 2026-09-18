@echo off
rem ===== 我的技术博客 启动脚本 =====
rem 双击后：启动本地博客服务器 + 自动打开浏览器
cd /d D:\Pythonproject\tech-blog
start "博客服务器" cmd /k "F:\develop\Anaconda3\envs\blog_env\Scripts\mkdocs.exe serve -a 127.0.0.1:8000"
timeout /t 3 /nobreak >nul
start http://127.0.0.1:8000
