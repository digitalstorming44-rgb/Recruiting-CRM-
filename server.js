const http = require("http");
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "public");
const port = Number(process.env.PORT || 4173);
const types = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
};

function handleRequest(request, response) {
  response.setHeader("X-Content-Type-Options", "nosniff");
  response.setHeader("Cache-Control", "no-cache");
  if (!["GET", "HEAD"].includes(request.method)) {
    response.setHeader("Allow", "GET, HEAD");
    response.writeHead(405).end("Method not allowed");
    return;
  }
  let requested;
  try {
    requested = decodeURIComponent(request.url.split("?")[0]);
    if (requested.includes("\0")) throw new Error("Invalid path");
  } catch {
    response.writeHead(400).end("Invalid request path");
    return;
  }
  const relative =
    requested === "/" ? "index.html" : requested.replace(/^\/+/, "");
  const file = path.resolve(root, relative);
  if (!file.startsWith(root + path.sep)) {
    response.writeHead(403).end("Forbidden");
    return;
  }
  return new Promise((resolve) =>
    fs.readFile(file, (error, data) => {
      if (!error) {
        response.writeHead(200, {
          "Content-Type":
            types[path.extname(file).toLowerCase()] ||
            "application/octet-stream",
        });
        response.end(request.method === "HEAD" ? undefined : data);
        resolve();
        return;
      }
      response
        .writeHead(
          ["ENOENT", "EISDIR", "ENOTDIR"].includes(error.code) ? 404 : 500,
        )
        .end(request.method === "HEAD" ? undefined : "File unavailable");
      resolve();
    }),
  );
}
if (require.main === module)
  http.createServer(handleRequest).listen(port, "127.0.0.1", () => {
    console.log(`Digital Storming CRM: http://localhost:${port}`);
  });
module.exports = { handleRequest };
