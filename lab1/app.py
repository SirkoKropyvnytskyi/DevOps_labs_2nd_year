import json
import sys
import psycopg2
from psycopg2.extras import RealDictCursor
from flask import Flask, request, jsonify, make_response

app = Flask(__name__)

# Читаємо конфігурацію з системної папки
CONFIG_PATH = '/etc/mywebapp/config.json'

def load_config():
    try:
        with open(CONFIG_PATH, 'r') as f:
            return json.load(f)
    except Exception as e:
        print(f"Error loading configuration: {e}")
        sys.exit(1)

config = load_config()

# Функція для підключення до БД
def get_db_connection():
    try:
        conn = psycopg2.connect(
            host=config.get('db_host', '127.0.0.1'),
            port=config.get('db_port', 5432),
            dbname=config.get('db_name', 'notes_db'),
            user=config.get('db_user', 'notes_user'),
            password=config.get('db_password', '123')
        )
        return conn
    except Exception as e:
        print(f"Error connecting to DB: {e}")
        return None

def wants_html():
    """Checks if the client expects a response in text/html format"""
    accept = request.headers.get('Accept', '')
    return 'text/html' in accept

# ==========================================
# HEALTH CHECKS
# ==========================================

@app.route('/health/alive', methods=['GET'])
def alive():
    """Always returns HTTP 200 with content OK (plain text)"""
    response = make_response("OK", 200)
    response.headers["Content-Type"] = "text/plain"
    return response

@app.route('/health/ready', methods=['GET'])
def ready():
    """Returns HTTP 200 with content OK if there is a connection to the DB, otherwise returns HTTP 500"""
    conn = get_db_connection()
    if conn:
        conn.close()
        response = make_response("OK", 200)
        response.headers["Content-Type"] = "text/plain"
        return response
    else:
        response = make_response("Database connection failed", 500)
        response.headers["Content-Type"] = "text/plain"
        return response

# ==========================================
# КОРЕНЕВИЙ ЕНДПОІНТ
# ==========================================

@app.route('/', methods=['GET'])
def index():
    """Checks if the client expects a response in text/html format and returns a list of all business endpoints"""
    html_content = """<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>My Web App - Ендпоінти</title>
</head>
<body>
    <title>My Web App - Ендпоінти</title>
</head>
<body>
    <h1>List of endpoints of the business logic of the application</h1>
    <ul>
        <li><strong>GET /notes</strong> — Display a list of all notes (id, title)</li>
        <li><strong>POST /notes</strong> — Create a new note (Fields: title, content)</li>
        <li><strong>GET /notes/&lt;id&gt;</strong> — Display the full content of a note (id, title, created_at, content)</li>
    </ul>
</body>
</html>"""
    response = make_response(html_content, 200)
    response.headers["Content-Type"] = "text/html"
    return response

# ==========================================
# БІЗНЕС-ЛОГІКА (Notes Service)
# ==========================================

@app.route('/notes', methods=['GET'])
def get_notes():
    """Display a list of all notes (id, title)"""
    conn = get_db_connection()
    if not conn:
        if wants_html():
            return make_response("<h1>Database connection failed</h1>", 500)
        return jsonify({"error": "DB connection failed"}), 500
    
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute("SELECT id, title FROM notes ORDER BY created_at DESC;")
    notes = cur.fetchall()
    cur.close()
    conn.close()
    
    # Обробка формату text/html
    if wants_html():
        table_rows = ""
        for note in notes:
            table_rows += f"<tr><td>{note['id']}</td><td><a href='/notes/{note['id']}'>{note['title']}</a></td></tr>"
            
        html_content = f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>List of notes</title>
</head>
<body>
    <h1>List of all notes</h1>
    <table border="1">
        <thead>
            <tr>
                <th>id</th>
                <th>title</th>
            </tr>
        </thead>
        <tbody>
            {table_rows}
        </tbody>
    </table>
</body>
</html>"""
        response = make_response(html_content, 200)
        response.headers["Content-Type"] = "text/html"
        return response
    
    # Обробка формату application/json (за замовчуванням)
    return jsonify(notes), 200

@app.route('/notes', methods=['POST'])
def create_note():
    """Create a new note (title, content)"""
    # Дозволяємо приймати і JSON, і звичайні HTML-форми для гнучкості тестування
    if request.is_json:
        data = request.get_json()
    else:
        data = request.form

    if not data or 'title' not in data or 'content' not in data:
        if wants_html():
            return make_response("<h1>Error: title and content are required</h1>", 400)
        return jsonify({"error": "Title and content are required"}), 400
    
    conn = get_db_connection()
    if not conn:
        if wants_html():
            return make_response("<h1>Database connection failed</h1>", 500)
        return jsonify({"error": "DB connection failed"}), 500
    
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute(
        "INSERT INTO notes (title, content) VALUES (%s, %s) RETURNING id, title, content, created_at;",
        (data['title'], data['content'])
    )
    new_note = cur.fetchone()
    conn.commit()
    cur.close()
    conn.close()
    
    # Конвертуємо дату в рядок, щоб вона коректно серіалізувалась
    new_note['created_at'] = str(new_note['created_at'])
    
    if wants_html():
        html_content = f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Note Created</title>
</head>
<body>
    <h1>Note created successfully!</h1>
    <p><strong>id:</strong> {new_note['id']}</p>
    <p><strong>title:</strong> {new_note['title']}</p>
    <p><strong>content:</strong> {new_note['content']}</p>
    <p><strong>created_at:</strong> {new_note['created_at']}</p>
</body>
</html>"""
        response = make_response(html_content, 201)
        response.headers["Content-Type"] = "text/html"
        return response
        
    return jsonify(new_note), 201

@app.route('/notes/<int:note_id>', methods=['GET'])
def get_note(note_id):
    """Display the full content of a note (id, title, created_at, content)"""
    conn = get_db_connection()
    if not conn:
        if wants_html():
            return make_response("<h1>Database connection failed</h1>", 500)
        return jsonify({"error": "DB connection failed"}), 500
    
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute("SELECT id, title, content, created_at FROM notes WHERE id = %s;", (note_id,))
    note = cur.fetchone()
    cur.close()
    conn.close()
    
    if not note:
        if wants_html():
            return make_response("<h1>Note not found</h1>", 404)
        return jsonify({"error": "Note not found"}), 404
        
    note['created_at'] = str(note['created_at'])
    
    if wants_html():
        html_content = f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>{note['title']}</title>
</head>
<body>
    <h1>Note details</h1>
    <p><strong>id:</strong> {note['id']}</p>
    <p><strong>title:</strong> {note['title']}</p>
    <p><strong>created_at:</strong> {note['created_at']}</p>
    <p><strong>content:</strong></p>
    <p>{note['content']}</p>
</body>
</html>"""
        response = make_response(html_content, 200)
        response.headers["Content-Type"] = "text/html"
        return response
        
    return jsonify(note), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=config.get('app_port', 5000))