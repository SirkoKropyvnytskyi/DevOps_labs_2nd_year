import json
import psycopg2
import sys

CONFIG_PATH = '/etc/mywebapp/config.json'

def load_config():
    try:
        with open(CONFIG_PATH, 'r') as f:
            return json.load(f)
    except Exception as e:
        print(f"Error loading configuration: {e}")
        sys.exit(1)

def migrate():
    config = load_config()
    
    try:
        conn = psycopg2.connect(
            host=config.get('db_host', '127.0.0.1'),
            port=config.get('db_port', 5432),
            dbname=config.get('db_name', 'notes_db'),
            user=config.get('db_user', 'notes_user'),
            password=config.get('db_password', '123')
        )
        
        cur = conn.cursor()
        
        create_table_query = """
        CREATE TABLE IF NOT EXISTS notes (
            id SERIAL PRIMARY KEY,
            title VARCHAR(255) NOT NULL,
            content TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        """
        cur.execute(create_table_query)
        
        create_index_query = """
        CREATE INDEX IF NOT EXISTS idx_notes_created_at ON notes(created_at);
        """
        cur.execute(create_index_query)
        
        conn.commit()
        
        cur.close()
        conn.close()
        
        print("Migration completed successfully! Table 'notes' and indexes are ready.")
        
    except Exception as e:
        print(f"Error during migration: {e}")
        sys.exit(1)

if __name__ == '__main__':
    migrate()