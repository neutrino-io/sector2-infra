#!/usr/bin/env python3
"""
Verification script to test ClickHouse Connect driver installation
"""

import sys

def test_clickhouse_connect():
    """Test if clickhouse-connect can be imported"""
    try:
        import clickhouse_connect
        print("✅ ClickHouse Connect driver installed successfully!")

        # Print version information
        try:
            version = clickhouse_connect.__version__
            print(f"   Version: {version}")
        except AttributeError:
            print("   Version: Unknown")

        # Test basic client creation (no actual connection)
        try:
            client = clickhouse_connect.get_client(host='localhost', port=8123)
            print("✅ ClickHouse Connect client can be instantiated")
            return True
        except Exception as e:
            print(f"⚠️  ClickHouse Connect client instantiation failed (expected without server): {e}")
            return True  # This is expected without a running server

    except ImportError as e:
        print(f"❌ ClickHouse Connect driver installation failed: {e}")
        return False

if __name__ == "__main__":
    success = test_clickhouse_connect()
    sys.exit(0 if success else 1)