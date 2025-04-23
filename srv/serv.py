from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
import json
import os
import time
import datetime
import ssl
import random
import string
import logging
import threading

# Modificar el formato del logging para usar successful/failed
logging.basicConfig(
    filename='api_key_requests.log',
    level=logging.INFO,
    format='%(asctime)s - %(status)s - IP: %(ip)s - Key: %(key)s - Message: %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)

# Configuración del servidor
USE_HTTPS = False  # Cambiar a True para usar HTTPS
SERVER_PORT = 1204

# Configuración SSL para HTTPS (solo se usa si USE_HTTPS es True)
if USE_HTTPS:
    ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ssl_context.load_cert_chain(
        '/etc/letsencrypt/live/stats.kmiras.com/fullchain.pem',
        keyfile='/etc/letsencrypt/live/stats.kmiras.com/privkey.pem'
    )

def generate_api_key():
    """Generate a random 16-character API key with 'ks-' prefix"""
    chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    key = ''.join(random.choice(chars) for _ in range(16))
    return f"ks-{key}"

# Añadir al principio del archivo, después de los imports
pending_confirmations = {}

class StatsHandler(BaseHTTPRequestHandler):
    def _set_headers(self, content_type='application/json'):
        self.send_response(200)
        self.send_header('Content-type', content_type)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def do_OPTIONS(self):
        self._set_headers()

    def do_GET(self):
        if self.path == '/':
            self._set_headers('text/html')
            if os.path.exists('index.html'):
                with open('index.html', 'rb') as file:
                    self.wfile.write(file.read())
            else:
                self.wfile.write('<html><body><h1>Error: No se encontró el archivo index.html</h1></body></html>'.encode('utf-8'))
        elif self.path == '/styles.css':
            self._set_headers('text/css')
            if os.path.exists('styles.css'):
                with open('styles.css', 'rb') as file:
                    self.wfile.write(file.read())
            else:
                self.send_error(404)
        elif self.path.startswith('/img/'):
            try:
                with open('.' + self.path, 'rb') as file:
                    self._set_headers('image/' + self.path.split('.')[-1])
                    self.wfile.write(file.read())
            except:
                self.send_error(404)
        elif self.path == '/api/keys':
            self._set_headers()
            response = json.dumps({"keys": []})
            self.wfile.write(response.encode())
        elif self.path == '/api/stats':
            self._set_headers()
            if os.path.exists('stats.json'):
                try:
                    with open('stats.json', 'r') as f:
                        stats_data = json.load(f)
                    response = json.dumps(stats_data)
                    self.wfile.write(response.encode())
                except Exception as e:
                    error_response = json.dumps({"error": f"Error al leer stats.json: {str(e)}"})
                    self.wfile.write(error_response.encode())
            else:
                error_response = json.dumps({"error": "No hay estadísticas disponibles"})
                self.wfile.write(error_response.encode())
        elif self.path == '/api/request_key':
            try:
                new_api_key = generate_api_key()
                client_ip = self.headers.get('X-Forwarded-For', self.client_address[0])
                
                # Registrar la generación inicial de la API key
                logging.info("API Key generated, waiting for client confirmation", extra={
                    'status': 'PENDING',
                    'ip': client_ip,
                    'key': new_api_key,
                })
                
                # Crear evento para cancelar el timer
                cancel_event = threading.Event()
                pending_confirmations[new_api_key] = cancel_event
                
                def check_confirmation():
                    # Esperar 5 segundos o hasta que el evento sea establecido
                    if not cancel_event.wait(5):
                        # Si no se recibió confirmación y la key aún está pendiente
                        if new_api_key in pending_confirmations:
                            logging.warning("No client confirmation received", extra={
                                'status': 'FAILED',
                                'ip': client_ip,
                                'key': new_api_key,
                            })
                            del pending_confirmations[new_api_key]
                
                threading.Thread(target=check_confirmation).start()
                
                self._set_headers()
                response = json.dumps({"api_key": new_api_key})
                self.wfile.write(response.encode())
                
            except Exception as e:
                logging.error(str(e), extra={
                    'status': 'FAILED',
                    'ip': self.client_address[0],
                    'key': 'None',
                })
                
                self.send_response(500)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                error_response = json.dumps({"error": str(e)})
                self.wfile.write(error_response.encode())
        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b'Not Found')

    def do_POST(self):
        if self.path == '/api/stats':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            
            try:
                stats_data = json.loads(post_data.decode('utf-8'))
                
                if os.path.exists('stats.json'):
                    try:
                        with open('stats.json', 'r') as f:
                            existing_stats = json.load(f)
                    except json.JSONDecodeError:
                        existing_stats = []
                else:
                    existing_stats = []
                
                if isinstance(stats_data, list):
                    existing_stats.extend(stats_data)
                else:
                    existing_stats.append(stats_data)
                
                with open('stats.json', 'w') as f:
                    json.dump(existing_stats, f, indent=2)
                
                self._set_headers()
                response = json.dumps({"status": "success", "message": "Estadísticas guardadas correctamente"})
                self.wfile.write(response.encode())
            except Exception as e:
                self.send_response(400)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                response = json.dumps({"status": "error", "message": f"Error al procesar estadísticas: {str(e)}"})
                self.wfile.write(response.encode())
        elif self.path == '/api/request_key/failed':
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length)
            
            try:
                data = json.loads(post_data.decode('utf-8'))
                client_ip = self.headers.get('X-Forwarded-For', self.client_address[0])
                
                logging.error("Client reported API key request failure", extra={
                    'status': 'CLIENT_ERROR',
                    'ip': client_ip,
                    'key': 'None'
                })
                
                self._set_headers()
                self.wfile.write(json.dumps({"status": "error logged"}).encode())
                
            except Exception as e:
                self.send_response(400)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e)}).encode())
        elif self.path == '/api/key/status':
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length)
            
            try:
                data = json.loads(post_data.decode('utf-8'))
                client_ip = self.headers.get('X-Forwarded-For', self.client_address[0])
                status = data.get('status')
                api_key = data.get('api_key')
                
                if status == "success":
                    # Cancelar el timer si existe
                    if api_key in pending_confirmations:
                        pending_confirmations[api_key].set()
                        del pending_confirmations[api_key]
                    
                    logging.info("Client confirmed successful API key reception", extra={
                        'status': 'SUCCESSFUL',
                        'ip': client_ip,
                        'key': api_key,
                    })
                elif status == "loaded_valid":
                    logging.info("Client loaded valid API key", extra={
                        'status': 'SUCCESSFUL',
                        'ip': client_ip,
                        'key': api_key
                    })
                elif status == "loaded_invalid":
                    logging.warning("Client loaded invalid API key", extra={
                        'status': 'REJECTED',  # Cambiado de 'FAILED' a 'REJECTED'
                        'ip': client_ip,
                        'key': api_key
                    })
                elif status == "invalid_format":
                    logging.error("Client reported invalid API key format", extra={
                        'status': 'FAILED',
                        'ip': client_ip,
                        'key': api_key
                    })
                elif status == "request_failed":
                    logging.error("Client reported failed API key request", extra={
                        'status': 'FAILED',
                        'ip': client_ip,
                        'key': 'None'
                    })
                
                self._set_headers()
                self.wfile.write(json.dumps({"status": "logged"}).encode())
                
            except Exception as e:
                self.send_response(400)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e)}).encode())
        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b'Not Found')

def run_server(port=SERVER_PORT):
    server_address = ('', port)
    httpd = ThreadingHTTPServer(server_address, StatsHandler)
    
    if USE_HTTPS:
        httpd.socket = ssl_context.wrap_socket(httpd.socket, server_side=True)
        print(f"Servidor HTTPS iniciado en el puerto {port}")
    else:
        print(f"Servidor HTTP iniciado en el puerto {port}")
    
    httpd.serve_forever()

if __name__ == '__main__':
    run_server()