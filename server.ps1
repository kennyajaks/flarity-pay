# Simple PowerShell Static File Web Server for Flarity Pay

$port = 8080
$rootPath = "C:\Users\kenny\.gemini\antigravity\scratch\flarity-pay"

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")

try {
    $listener.Start()
    Write-Host "Server successfully started on http://localhost:$port"
    Write-Host "Press Ctrl+C in terminal or terminate the task to stop."
} catch {
    Write-Error "Failed to start listener: $_"
    exit 1
}

while ($listener.IsListening) {
    try {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        
        # Resolve request URL to local path
        $url = $request.RawUrl.Split('?')[0] # Remove query parameters
        if ($url -eq "/" -or $url -eq "") {
            $url = "/index.html"
        }
        
        $cleanUrl = $url.TrimStart('/')
        $filePath = [System.IO.Path]::Combine($rootPath, $cleanUrl)
        
        # Verify file is inside the root directory to prevent directory traversal
        $fullPath = [System.IO.Path]::GetFullPath($filePath)
        $rootFullPath = [System.IO.Path]::GetFullPath($rootPath)
        
        if (-not $fullPath.StartsWith($rootFullPath)) {
            $response.StatusCode = 403
            $response.Close()
            continue
        }

        if (Test-Path $filePath -PathType Leaf) {
            $bytes = [System.IO.File]::ReadAllBytes($filePath)
            
            # Content Type Mapping
            $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
            switch ($ext) {
                ".html" { $response.ContentType = "text/html" }
                ".css"  { $response.ContentType = "text/css" }
                ".js"   { $response.ContentType = "application/javascript" }
                ".jpg"  { $response.ContentType = "image/jpeg" }
                ".jpeg" { $response.ContentType = "image/jpeg" }
                ".png"  { $response.ContentType = "image/png" }
                ".svg"  { $response.ContentType = "image/svg+xml" }
                default { $response.ContentType = "application/octet-stream" }
            }
            
            # Set CORS header to allow external Web3 RPC queries if needed
            $response.Headers.Add("Access-Control-Allow-Origin", "*")
            $response.ContentLength64 = $bytes.Length
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $response.StatusCode = 404
            $errBytes = [System.Text.Encoding]::UTF8.GetBytes("404 - File Not Found")
            $response.ContentLength64 = $errBytes.Length
            $response.OutputStream.Write($errBytes, 0, $errBytes.Length)
        }
        
        $response.Close()
    } catch {
        # Silent fail on single connection drops to keep listener alive
    }
}
$listener.Close()
