"""QR code for frictionless party join.

The TV lobby shows the room code; this endpoint renders a scannable QR PNG
of the join URL so guests can join from their phone camera with no typing.
``GET /native/qr/<room_code>`` -> image/png. No room lookup is performed --
the code is only validated for shape, so the TV can render it before any
phone has joined.
"""

import io
import os
import re

from flask import Blueprint, Response, abort

qr_bp = Blueprint("native_qr", __name__)

_CODE_RE = re.compile(r"^[A-Z2-9]{6}$")


@qr_bp.route("/native/qr/<code>")
def join_qr(code: str):
    code = (code or "").upper()
    if not _CODE_RE.match(code):
        abort(404)
    base = os.environ.get("NATIVE_JOIN_URL_BASE",
                          "https://aurora.app/join").rstrip("/")
    url = f"{base}/{code}"
    try:
        import qrcode
    except ImportError:  # pragma: no cover - dependency missing
        abort(501)
    img = qrcode.make(url, box_size=10, border=2)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return Response(buf.getvalue(), mimetype="image/png",
                    headers={"Cache-Control": "no-store"})
