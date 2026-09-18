# 我的技术博客

基于 [MkDocs](https://www.mkdocs.org/) + Material 主题搭建的静态技术博客。

## 本地运行

```powershell
cd D:\Pythonproject\tech-blog
F:\develop\Anaconda3\envs\blog_env\Scripts\mkdocs.exe serve -a 127.0.0.1:8000
```

浏览器打开 http://127.0.0.1:8000

也可以直接双击桌面「我的技术博客」图标（会自动启动服务器并打开浏览器）。

## 写新文章

在 `docs/posts/` 下新建 Markdown 文件，然后在 `mkdocs.yml` 的 `nav` 中加一行即可。

## 发布到 GitHub Pages

```powershell
cd D:\Pythonproject\tech-blog
git add .
git commit -m "更新博客"
F:\develop\Anaconda3\envs\blog_env\Scripts\mkdocs.exe gh-deploy
```
