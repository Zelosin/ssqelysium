# Serve Godot Web export over HTTP (do not open HTML via file://).
param(
	[int]$Port = 8060
)

$buildRoot = $PSScriptRoot
$webDir = Join-Path $buildRoot "web"
if (-not (Test-Path $webDir)) {
	Write-Error "Folder not found: $webDir. Export Web preset to build/web/index.html"
	exit 1
}

$serveDir = (Resolve-Path $webDir).Path
$entry = "index.html"
if (-not (Test-Path (Join-Path $serveDir $entry))) {
	$entry = "test.html"
	if (-not (Test-Path (Join-Path $serveDir $entry))) {
		Write-Error "No index.html or test.html in build/web"
		exit 1
	}
}

$url = "http://localhost:$Port/$entry"
Write-Host "Folder: $serveDir"
Write-Host "Open:   $url"
Write-Host "Press Ctrl+C to stop."

$mime = @{
	".html" = "text/html; charset=utf-8"
	".js"   = "application/javascript; charset=utf-8"
	".wasm" = "application/wasm"
	".pck"  = "application/octet-stream"
	".png"  = "image/png"
	".ico"  = "image/x-icon"
	".json" = "application/json"
}

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()

try {
	if ([string]::IsNullOrEmpty([System.Environment]::GetEnvironmentVariable("NO_BROWSER"))) {
		Start-Process $url
	}
	while ($listener.IsListening) {
		$context = $listener.GetContext()
		$rel = $context.Request.Url.LocalPath.TrimStart("/")
		if ([string]::IsNullOrEmpty($rel)) {
			$rel = $entry
		}
		$file = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($serveDir, $rel.Replace("/", "\")))
		if (-not $file.StartsWith($serveDir, [StringComparison]::OrdinalIgnoreCase)) {
			$context.Response.StatusCode = 403
			$context.Response.Close()
			continue
		}
		if (-not (Test-Path $file -PathType Leaf)) {
			$context.Response.StatusCode = 404
			$context.Response.Close()
			Write-Host ('404 ' + $rel)
			continue
		}
		$ext = [System.IO.Path]::GetExtension($file).ToLowerInvariant()
		$bytes = [System.IO.File]::ReadAllBytes($file)
		$context.Response.StatusCode = 200
		if ($mime.ContainsKey($ext)) {
			$context.Response.ContentType = $mime[$ext]
		}
		$context.Response.ContentLength64 = $bytes.Length
		$context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
		$context.Response.Close()
	}
} finally {
	$listener.Stop()
}
