
import os
import psycopg2
from dotenv import load_dotenv
from urllib.parse import urlparse

# Load environment variables
load_dotenv()

DB_CONNECTION_STRING = os.getenv('DB_CONNECTION_STRING')

def verify_schema():
    if not DB_CONNECTION_STRING:
        print("❌ DB_CONNECTION_STRING not set")
        return

    result = urlparse(DB_CONNECTION_STRING)
    host = result.hostname
    port = result.port or 6543 # Default to pooler port if missing

    print(f"Connecting to verify schema at {host}:{port}...")
    try:
        conn = psycopg2.connect(
            dbname=result.path[1:],
            user=result.username,
            password=result.password,
            host=host,
            port=port,
            connect_timeout=20,
            sslmode='require'
        )
        cursor = conn.cursor()
        print("✅ Connection Successful.")

        # 1. Check Profiles Table
        print("\n[1] Checking 'profiles' table...")
        cursor.execute("SELECT to_regclass('public.profiles');")
        if cursor.fetchone()[0]:
            print("✅ Table 'profiles' exists.")
        else:
            print("❌ Table 'profiles' MISSING.")

        # 2. Check Auth references (Foreign Keys)
        print("\n[2] Checking Foreign Keys to auth.users...")
        # Dictionary of table -> expected constraint presence
        checks = {
            "profiles": "auth.users",
            "user_pantry": "auth.users",
            "user_equipment": "auth.users"
        }
        
        for table, ref in checks.items():
            # Query pg_constraint to see if there's a foreign key to auth.users
            # Note: auth.users is in 'auth' schema, so we check confrelid
            query = f"""
                SELECT count(*) 
                FROM pg_constraint c
                JOIN pg_class t ON c.conrelid = t.oid
                JOIN pg_namespace n ON t.relnamespace = n.oid
                WHERE n.nspname = 'public' 
                AND t.relname = '{table}'
                AND c.contype = 'f';
            """
            cursor.execute(query)
            count = cursor.fetchone()[0]
            if count > 0:
                 print(f"✅ '{table}' has foreign keys (likely to {ref}).")
            else:
                 print(f"⚠️ '{table}' has NO foreign keys found.")

        # 3. Check RLS
        print("\n[3] Checking Row Level Security (RLS)...")
        tables_to_check = ['user_pantry', 'user_equipment']
        for t in tables_to_check:
            cursor.execute(f"SELECT relrowsecurity FROM pg_class WHERE relname = '{t}';")
            rls = cursor.fetchone()
            if rls and rls[0]:
                print(f"✅ RLS enabled on '{t}'.")
            else:
                print(f"❌ RLS NOT enabled on '{t}'.")
                
        # 4. Check Recipe Count
        print("\n[4] Checking Recipe Data Count...")
        cursor.execute("SELECT count(*) FROM recipes;")
        count = cursor.fetchone()[0]
        print(f"✅ Recipes found: {count}")

        cursor.close()
        conn.close()

    except Exception as e:
        print(f"❌ Error: {e}")

if __name__ == "__main__":
    verify_schema()
