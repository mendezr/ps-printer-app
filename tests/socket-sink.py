#!/usr/bin/env python3
import socket
import sys

port = int(sys.argv[1])
output_path = sys.argv[2]

with socket.socket() as listener:
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", port))
    listener.listen(1)
    listener.settimeout(120)
    connection, _ = listener.accept()
    connection.settimeout(30)
    with connection, open(output_path, "wb") as output:
        while data := connection.recv(65536):
            output.write(data)
