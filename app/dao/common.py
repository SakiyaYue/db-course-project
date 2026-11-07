"""Single execution/result reader; drain all result sets so deferred SQL errors surface."""
from contextlib import contextmanager

@contextmanager
def cursor_scope(conn):
    cursor = conn.cursor()
    try:
        yield cursor
    finally:
        cursor.close()

def first_result(cursor):
    result = None
    while True:
        if cursor.description:
            columns = [column[0] for column in cursor.description]
            rows = [dict(zip(columns, row)) for row in cursor.fetchall()]
            if result is None:
                result = rows
        if not cursor.nextset():
            break
    return result or []

def query(conn, sql, *parameters):
    with cursor_scope(conn) as cursor:
        cursor.execute(sql, *parameters)
        return first_result(cursor)

def procedure(conn, sql, *parameters):
    return query(conn, sql, *parameters)

def transaction_count(conn):
    return int(query(conn, "SELECT @@TRANCOUNT AS count")[0]["count"])

def health(conn):
    query(conn, "SELECT 1 AS alive")
