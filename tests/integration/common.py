"""Connection and exact result metadata helpers; credentials only from environment."""
import json
import os
import re
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACTS = json.loads((ROOT / 'tests/integration/contracts.json').read_text())


def connect():
    import pytds
    return pytds.connect(os.environ['STACKISH_SERVER'], database=os.environ['STACKISH_DATABASE'],
                        user=os.environ['STACKISH_USER'], password=os.environ['SQLCMDPASSWORD'],
                        autocommit=True, timeout=int(os.environ.get('STACKISH_TIMEOUT', '600')),
                        appname='Stackish integration')


def sql_type(serializer):
    from pytds import tds_base as t
    if type(serializer).__name__.startswith('NVarCharMax'): return 'nvarchar(max)'
    if type(serializer).__name__.startswith('VarCharMax'): return 'varchar(max)'
    code = serializer.get_typeid()
    scalar = {t.SYBINT1: 'tinyint', t.SYBINT2: 'smallint', t.SYBINT4: 'int', t.SYBINT8: 'bigint', t.SYBBIT: 'bit',
              t.SYBDATETIME: 'datetime', t.SYBUNIQUE: 'uniqueidentifier'}
    if code in scalar:
        return scalar[code]
    text = {t.XSYBNVARCHAR: 'nvarchar', t.XSYBVARCHAR: 'varchar', t.XSYBNCHAR: 'nchar', t.XSYBCHAR: 'char'}
    if code in text:
        size = 'max' if 'Max' in type(serializer).__name__ else str(int(serializer.size))
        return f'{text[code]}({size})'
    raise AssertionError(f'Unhandled SQL type: {code}, {serializer!r}')


def results(cursor):
    sets = []
    while True:
        if cursor.description is not None:
            # DB-API maps both int/bigint to int and varchar/nvarchar to str. Read TDS
            # column metadata to distinguish them, including all empty result sets.
            shape = [[c.column_name, sql_type(c.serializer)] for c in cursor._session.res_info.columns]
            sets.append((shape, [tuple(r) for r in cursor.fetchall()]))
        if not cursor.nextset():
            return sets


def query(connection, sql, params=()):
    with connection.cursor() as cursor:
        cursor.execute(sql, params or None)
        return results(cursor)


def rows(connection, sql, params=()):
    return query(connection, sql, params)[0][1]


def scalar(connection, sql, params=()):
    return rows(connection, sql, params)[0][0]


def emit(label, **details):
    print(json.dumps({'check': label, **details}, default=str), flush=True)


def call(connection, name, expected=None, **params):
    full = 'Stackish_' + name
    sql = f'EXEC dbo.{full} ' + ','.join('@'+key+'=%s' for key in params)
    start = time.monotonic()
    try:
        sets = query(connection, sql, tuple(params.values()))
        actual = [s[0] for s in sets]
        assert actual == CONTRACTS[full]['results'], (name, 'result shape', actual)
        if expected:
            assert sets[0][1] and sets[0][1][0][0] == expected, (name, expected, sets)
        emit(name, milliseconds=round((time.monotonic()-start)*1000, 2),
             rows=[len(s[1]) for s in sets],
             outcome=sets[0][1][0][0] if CONTRACTS[full]['results'][0][0][0]=='Outcome' and sets[0][1] else None)
        return [s[1] for s in sets]
    except Exception as exc:
        emit(name, error=str(exc), milliseconds=round((time.monotonic()-start)*1000,2))
        raise


def batches(path):
    """Only GO and repository-relative :r/:ON ERROR EXIT; never changes database."""
    text = path.read_text()
    pending = []
    for line in text.splitlines():
        if line.lower().startswith(':r '):
            assert not '\n'.join(pending).strip(), path
            yield from batches(ROOT / line[3:].strip())
        elif line.upper().startswith(':ON ERROR EXIT'):
            continue
        elif re.fullmatch(r'\s*GO\s*', line, re.I):
            if '\n'.join(pending).strip():
                yield '\n'.join(pending)
            pending=[]
        elif line.lstrip().startswith('--') and not pending:
            continue
        else:
            pending.append(line)
    if '\n'.join(pending).strip():
        yield '\n'.join(pending)
