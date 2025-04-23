#!/usr/bin/env python3

import http.server
import socketserver
import ssl
import threading
import os

# Configuración del dominio
DOMAIN = "stats.kmiras.com"  # Cambia esto por tu dominio
HTML_FILE = "build.html"     # Archivo HTML a servir

# Rutas de los certificados de Let's Encrypt
SSL_CERT = f"/etc/letsencrypt/live/{DOMAIN}/fullchain.pem"
SSL_KEY = f"/etc/letsencrypt/live/{DOMAIN}/privkey.pem"

# Verificar que el archivo HTML existe
if not os.path.exists(HTML_FILE):
    with open(HTML_FILE, 'w') as f:
        f.write("<html><body><h1>Página de prueba</h1></body></html>")
    print(f"Archivo {HTML_FILE} creado con contenido básico")

# Manejador personalizado para HTTPS
class HTTPSHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/':
            self.path = f"/{HTML_FILE}"
        elif self.path == '/favicon.ico':
            self.path = '../img/favicon.ico'
            if not os.path.exists(self.path):
                self.send_error(404, "Favicon not found")
                return
        return http.server.SimpleHTTPRequestHandler.do_GET(self)

# Manejador para redirección HTTP a HTTPS
class HTTPRedirectHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(301)  # Redirección permanente
        new_url = f"https://{DOMAIN}{self.path}"
        self.send_header('Location', new_url)
        self.end_headers()
        
    def do_POST(self):
        self.send_response(301)
        new_url = f"https://{DOMAIN}{self.path}"
        self.send_header('Location', new_url)
        self.end_headers()

# Función para iniciar el servidor HTTPS
def run_https_server():
    https_server = socketserver.TCPServer(("", 443), HTTPSHandler)
    
    # Configurar SSL
    https_server.socket = ssl.wrap_socket(
        https_server.socket,
        keyfile=SSL_KEY,
        certfile=SSL_CERT,
        server_side=True
    )
    
    print("Servidor HTTPS iniciado en el puerto 443")
    https_server.serve_forever()

# Función para iniciar el servidor HTTP de redirección
def run_http_redirect_server():
    http_server = socketserver.TCPServer(("", 80), HTTPRedirectHandler)
    print("Servidor HTTP de redirección iniciado en el puerto 80")
    http_server.serve_forever()

# Iniciar ambos servidores en hilos separados
if __name__ == "__main__":
    # Comprobar si los certificados existen
    if not os.path.exists(SSL_CERT) or not os.path.exists(SSL_KEY):
        print(f"Error: No se encontraron los certificados de Let's Encrypt en {SSL_CERT}")
        print("Debes obtener certificados usando certbot antes de ejecutar este script.")
        exit(1)
        
    # Iniciar servidor HTTPS en un hilo
    https_thread = threading.Thread(target=run_https_server)
    https_thread.daemon = True
    https_thread.start()
    
    # Iniciar servidor HTTP de redirección en el hilo principal
    run_http_redirect_server()