#!/usr/bin/env python3
"""
Custom ClickHouse engine specification for Superset
This module provides a custom engine that can connect to Railway ClickHouse
using the clickhouse-driver directly, bypassing SQLAlchemy dialect issues.
"""

import logging
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine
from clickhouse_driver import Client

log = logging.getLogger(__name__)

class ClickHouseRailwayEngine:
    """Custom ClickHouse engine for Railway compatibility"""

    def __init__(self, uri: str):
        self.uri = uri
        self.client = None
        self._parse_uri()

    def _parse_uri(self):
        """Parse the ClickHouse URI to extract connection parameters"""
        # Parse clickhouse+native://username:password@host:port/database
        if self.uri.startswith('clickhouse+native://'):
            # Remove the prefix
            connection_str = self.uri.replace('clickhouse+native://', '')

            # Parse username:password@host:port/database
            if '@' in connection_str:
                auth_part, host_port_db = connection_str.split('@', 1)
                if ':' in auth_part:
                    self.username = auth_part.split(':')[0]
                    self.password = auth_part.split(':', 1)[1]
                    # Handle double dollar sign escaping from environment variables
                    if self.password.startswith('$$'):
                        self.password = '$' + self.password[2:]
                else:
                    self.username = auth_part
                    self.password = ''
            else:
                self.username = 'default'
                self.password = ''
                host_port_db = connection_str

            # Parse host:port/database
            if '/' in host_port_db:
                host_port, self.database = host_port_db.split('/', 1)
            else:
                host_port = host_port_db
                self.database = 'default'

            if ':' in host_port:
                self.host = host_port.split(':')[0]
                self.port = int(host_port.split(':')[1])
            else:
                self.host = host_port
                self.port = 9000
        else:
            raise ValueError(f"Unsupported URI format: {self.uri}")

    def connect(self):
        """Create a ClickHouse client connection"""
        try:
            self.client = Client(
                host=self.host,
                port=self.port,
                user=self.username,
                password=self.password,
                database=self.database
            )
            # Test connection
            self.client.execute('SELECT 1')
            log.info(f"Successfully connected to ClickHouse at {self.host}:{self.port}")
            return self.client
        except Exception as e:
            log.error(f"Failed to connect to ClickHouse: {e}")
            raise

    def execute(self, query: str, **kwargs):
        """Execute a query using the clickhouse-driver client"""
        if not self.client:
            self.connect()

        try:
            result = self.client.execute(query, **kwargs)

            # Convert clickhouse-driver format to something more standard
            if isinstance(result, list) and len(result) > 0:
                if isinstance(result[0], tuple):
                    # Return list of dicts for better compatibility
                    columns = [f'col_{i}' for i in range(len(result[0]))]
                    return [dict(zip(columns, row)) for row in result]
                else:
                    return result
            return result

        except Exception as e:
            log.error(f"Query execution failed: {e}")
            raise

    def get_table_names(self):
        """Get list of tables in the database"""
        try:
            result = self.execute('SHOW TABLES')
            return [list(row.values())[0] for row in result] if result else []
        except Exception as e:
            log.error(f"Failed to get table names: {e}")
            return []

    def get_columns(self, table_name: str):
        """Get column information for a table"""
        try:
            result = self.execute(f'DESCRIBE TABLE {table_name}')
            columns = []
            for row in result:
                if isinstance(row, dict):
                    columns.append({
                        'name': list(row.values())[0],
                        'type': list(row.values())[1],
                        'nullable': True  # ClickHouse columns are generally nullable
                    })
            return columns
        except Exception as e:
            log.error(f"Failed to get columns for table {table_name}: {e}")
            return []

def create_railway_engine(uri: str) -> ClickHouseRailwayEngine:
    """Factory function to create a Railway ClickHouse engine"""
    return ClickHouseRailwayEngine(uri)

# Test function
def test_railway_connection():
    """Test the Railway ClickHouse connection"""
    try:
        # Railway ClickHouse URI
        railway_uri = 'clickhouse+native://default:$$74qimqfukgop1ega34t2znnswagku88v@nozomi.proxy.rlwy.net:23230/default'

        engine = create_railway_engine(railway_uri)

        # Test basic connection
        result = engine.execute('SELECT 1 as test_value')
        print(f'✅ Custom engine connection successful! Test query returned: {result}')

        # Test ClickHouse version
        version_result = engine.execute('SELECT version() as version')
        print(f'✅ ClickHouse version: {version_result}')

        # List available databases
        databases = engine.execute('SHOW DATABASES')
        db_names = [list(row.values())[0] for row in databases] if databases else []
        print(f'✅ Available databases: {db_names}')

        # List tables
        tables = engine.get_table_names()
        print(f'✅ Available tables: {tables}')

        return True

    except Exception as e:
        print(f'❌ Custom engine connection failed: {e}')
        return False

if __name__ == '__main__':
    test_railway_connection()