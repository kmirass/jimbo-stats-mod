from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
import json
import os
import time
import datetime

# Lista para almacenar las API keys generadas
api_keys = []
next_key_id = 1

# Cargar API keys existentes si el archivo existe
if os.path.exists('apikeys.json'):
    try:
        with open('apikeys.json', 'r') as f:
            lines = f.readlines()
            for line in lines:
                if line.strip():
                    try:
                        key_data = json.loads(line.strip())
                        api_keys.append(key_data)
                        # Actualizar el próximo ID basado en el máximo ID encontrado
                        if 'id' in key_data and key_data['id'] >= next_key_id:
                            next_key_id = key_data['id'] + 1
                    except json.JSONDecodeError:
                        print(f"Error al parsear línea en apikeys.json: {line}")
    except Exception as e:
        print(f"Error al cargar apikeys.json: {e}")
else:
    # Crear el archivo si no existe
    with open('apikeys.json', 'w') as f:
        pass

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
            # Mostrar la página HTML
            self._set_headers('text/html')
            if os.path.exists('index.html'):
                with open('index.html', 'rb') as file:
                    self.wfile.write(file.read())
            else:
                # Si no existe el archivo index.html, crear una respuesta HTML básica
                self.wfile.write('<html><body><h1>Error: No se encontró el archivo index.html</h1></body></html>'.encode('utf-8'))
        elif self.path == '/api/keys':
            # Devolver la lista de API keys en formato JSON
            self._set_headers()
            response = json.dumps({"keys": api_keys})
            self.wfile.write(response.encode())
        elif self.path == '/api/stats':
            # Devolver las estadísticas de juego
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
        else:
            # Ruta no encontrada
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b'Not Found')

    def do_POST(self):
        global next_key_id
        
        if self.path == '/api/new_key':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            
            try:
                data = json.loads(post_data.decode('utf-8'))
                if 'api_key' in data:
                    # Registrar la nueva API key
                    api_key = data['api_key']
                    
                    # Verificar si la API key ya existe
                    key_exists = False
                    for key_data in api_keys:
                        if isinstance(key_data, dict) and key_data.get('key') == api_key:
                            key_exists = True
                            break
                        elif key_data == api_key:
                            key_exists = True
                            break
                    
                    if not key_exists:
                        # Crear objeto de API key con ID y fecha
                        key_obj = {
                            "id": next_key_id,
                            "key": api_key,
                            "date": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                        }
                        
                        # Añadir a la lista en memoria
                        api_keys.append(key_obj)
                        
                        # Guardar en el archivo apikeys.json (una por línea)
                        with open('apikeys.json', 'a') as f:
                            f.write(json.dumps(key_obj) + '\n')
                        
                        print(f"Nueva API key registrada: {api_key} con ID {next_key_id}")
                        
                        # Incrementar el contador para la próxima API key
                        next_key_id += 1
                    
                    # Responder con éxito
                    self._set_headers()
                    response = json.dumps({"status": "success", "message": "API key registrada correctamente"})
                    self.wfile.write(response.encode())
                else:
                    # Falta la API key en los datos
                    self.send_response(400)
                    self.send_header('Content-type', 'application/json')
                    self.end_headers()
                    response = json.dumps({"status": "error", "message": "Falta el campo api_key"})
                    self.wfile.write(response.encode())
            except json.JSONDecodeError:
                # Error al decodificar JSON
                self.send_response(400)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                response = json.dumps({"status": "error", "message": "JSON inválido"})
                self.wfile.write(response.encode())
        elif self.path == '/api/stats':
            # Endpoint para recibir estadísticas de juego
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            
            try:
                stats_data = json.loads(post_data.decode('utf-8'))
                
                # Guardar las estadísticas en stats.json
                if os.path.exists('stats.json'):
                    try:
                        with open('stats.json', 'r') as f:
                            existing_stats = json.load(f)
                    except json.JSONDecodeError:
                        existing_stats = []
                else:
                    existing_stats = []
                
                # Añadir las nuevas estadísticas
                if isinstance(stats_data, list):
                    existing_stats.extend(stats_data)
                else:
                    existing_stats.append(stats_data)
                
                # Guardar las estadísticas actualizadas
                with open('stats.json', 'w') as f:
                    json.dump(existing_stats, f, indent=2)
                
                # Responder con éxito
                self._set_headers()
                response = json.dumps({"status": "success", "message": "Estadísticas guardadas correctamente"})
                self.wfile.write(response.encode())
            except Exception as e:
                # Error al procesar las estadísticas
                self.send_response(400)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                response = json.dumps({"status": "error", "message": f"Error al procesar estadísticas: {str(e)}"})
                self.wfile.write(response.encode())
        else:
            # Ruta no encontrada
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b'Not Found')

def run_server(port=8080):
    server_address = ('', port)
    httpd = ThreadingHTTPServer(server_address, StatsHandler)
    print(f"Servidor iniciado en el puerto {port}")
    httpd.serve_forever()

if __name__ == '__main__':
    run_server()
