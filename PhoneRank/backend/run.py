import argparse
import logging
from waitress import serve
from app import create_app

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--lan', action='store_true', help='Expose read-only catalog to your LAN; admin remains loopback-only.')
    parser.add_argument('--port', type=int, default=8765)
    options = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
    print(f'Admin: http://127.0.0.1:{options.port}/', flush=True)
    serve(create_app(), host='0.0.0.0' if options.lan else '127.0.0.1', port=options.port, threads=4, max_request_body_size=3_000_000)
