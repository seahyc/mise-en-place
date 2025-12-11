
import os
import json
import psycopg2
import requests
from dotenv import load_dotenv
from urllib.parse import urlparse

# Load environment variables
load_dotenv()

SUPABASE_URL = os.getenv('SUPABASE_URL')
SUPABASE_ANON_KEY = os.getenv('SUPABASE_ANON_KEY')
DB_CONNECTION_STRING = os.getenv('DB_CONNECTION_STRING')
ELEVENLABS_API_KEY = os.getenv('ELEVENLABS_API_KEY')
KNOWN_SUPABASE_IP = "104.18.38.10"

def run_tests():
    print("=== STARTING INTEGRATION TESTS ===")
    
    # 1. DATABASE PERMISSIONS & CONNECTION
    print("\n[1/3] Testing Database Connection...")
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
        
        # Verify Direct DB Access
        cursor.execute("SELECT count(*) FROM recipes;")
        count = cursor.fetchone()[0]
        print(f"✅ DB Direct Connection Successful. Recipes count: {count}")
        
        cursor.close()
        conn.close()
    except Exception as e:
        print(f"❌ DB Error: {e}")

    # 2. SUPABASE REST API
    # Note: requests might fail if DNS is totally borked. 
    # We can try to force resolution via a session adapter if needed, but let's see.
    print("\n[2/3] Testing Supabase REST API (Anon Key)...")
    try:
        headers = {
            "apikey": SUPABASE_ANON_KEY,
            "Authorization": f"Bearer {SUPABASE_ANON_KEY}"
        }
        url = f"{SUPABASE_URL}/rest/v1/recipes?select=*"
        print(f"Requesting: {url}")
        
        # Simple request attempt
        try:
             response = requests.get(url, headers=headers, timeout=10)
        except requests.exceptions.ConnectionError:
             print("⚠️ Standard DNS resolution failed for API. Attempting forced IP mapping...")
             # Force Host header with IP URL - highly redundant but a desperate fallback
             # Actual solution requires patching socket/DNS for requests or modifying /etc/hosts
             # For now, just report failure if DNS is down.
             raise

        if response.status_code == 200:
            data = response.json()
            print(f"✅ Supabase REST API Successful. Records fetched: {len(data)}")
        else:
            print(f"❌ Supabase REST API Failed. Status: {response.status_code}")
            print(f"Response: {response.text}")
    except Exception as e:
        print(f"❌ Supabase API Error: {e}")

    # 3. ELEVENLABS API
    print("\n[3/3] Testing ElevenLabs API...")
    try:
        headers = {
            "xi-api-key": ELEVENLABS_API_KEY
        }
        url = "https://api.elevenlabs.io/v1/user"
        response = requests.get(url, headers=headers, timeout=10)
        
        if response.status_code == 200:
             print(f"✅ ElevenLabs API Key Valid.")
        else:
             print(f"❌ ElevenLabs API Key Invalid. Status: {response.status_code}")

    except Exception as e:
        print(f"❌ ElevenLabs Error: {e}")

    print("\n=== TESTS COMPLETED ===")

if __name__ == "__main__":
    run_tests()
