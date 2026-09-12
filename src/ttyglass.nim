import std/[asyncdispatch, asynchttpserver]

const
  address = "127.0.0.1"
  port = Port(8080)
  plainTextHeaders = [("Content-Type", "text/plain; charset=utf-8")]

proc handleRequest(request: Request) {.async.} =
  let headers = plainTextHeaders.newHttpHeaders()

  if request.reqMethod == HttpGet and request.url.path == "/":
    await request.respond(Http200, "Hello, World!\n", headers)
  else:
    await request.respond(Http404, "Not Found\n", headers)

proc main() =
  var server = newAsyncHttpServer()
  echo "Listening on http://", address, ":", port.uint16
  waitFor server.serve(port, handleRequest, address)

when isMainModule:
  main()
