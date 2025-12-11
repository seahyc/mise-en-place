
import os
import psycopg2
from dotenv import load_dotenv
from urllib.parse import urlparse

# Load environment variables
load_dotenv()

DB_CONNECTION_STRING = os.getenv('DB_CONNECTION_STRING')
KNOWN_SUPABASE_IP = "104.18.38.10"

def fix_schema():
    print(f"Connecting to database...")
    try:
        result = urlparse(DB_CONNECTION_STRING)
        conn = psycopg2.connect(
            dbname=result.path[1:],
            user=result.username,
            password=result.password,
            host=result.hostname,
            hostaddr=KNOWN_SUPABASE_IP,
            port=result.port,
            connect_timeout=10,
            sslmode='require'
        )
        conn.autocommit = True
        cursor = conn.cursor()

        print("✅ Connection Established.")
        
        # Check existing tables
        cursor.execute("""
            SELECT table_name 
            FROM information_schema.tables 
            WHERE table_schema = 'public';
        """)
        tables = cursor.fetchall()
        print(f"📊 Accessing Public Schema. Found {len(tables)} tables:")
        if not tables:
            print("⚠️  NO TABLES FOUND. The database is empty.")
        else:
            for t in tables:
                print(f" - {t[0]}")

        # Permissions (only useful if tables exist, but running anyway to prep for seeding)
        print("Granting usage...")
        cursor.execute("GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;")
        cursor.execute("GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;")
        cursor.execute("GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;")
        cursor.execute("NOTIFY pgrst, 'reload config';")
        print("✅ Permissions fixed.")
        
        cursor.close()
        conn.close()

    except Exception as e:
        print(f"❌ Error: {e}")

if __name__ == "__main__":
    fix_schema()
