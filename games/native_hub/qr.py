"""QR code + landing page for frictionless party join.

The TV lobby shows the room code; ``GET /native/qr/<room_code>`` renders a
scannable QR PNG of ``/join/<room_code>`` on this same server, so a guest's
camera opens a page that hands the code straight to the Aurora Play app
(``auroraplay://join/<code>`` -- registered in the iOS app's Info.plist)
and shows it large as a fallback. No room lookup is performed -- the code
is only validated for shape, so the TV can render it before any phone has
joined.

``NATIVE_JOIN_URL_BASE`` overrides the join URL base (e.g. a LAN address
``http://192.168.1.20:5000/join`` when hosting a party offline).

``NATIVE_TESTFLIGHT_URL`` sets the TestFlight install link shown on the
join page (e.g. ``https://testflight.apple.com/join/ABCDEF``). When unset,
the page shows a placeholder telling guests to ask the host for the invite.
"""

import io
import os
import re

from flask import Blueprint, Response, abort, render_template, request

qr_bp = Blueprint("native_qr", __name__)

_CODE_RE = re.compile(r"^[A-Z2-9]{6}$")


def testflight_url() -> str:
    """TestFlight invite link for the controller app ("" = placeholder)."""
    return os.environ.get("NATIVE_TESTFLIGHT_URL", "").strip()


def join_url_base() -> str:
    """Where the QR points: env override, else this server's own /join."""
    override = os.environ.get("NATIVE_JOIN_URL_BASE", "").strip()
    if override:
        return override.rstrip("/")
    # Render (and most hosts) terminate TLS at a proxy, so the WSGI scheme
    # is http even though phones reach us over https.
    scheme = (request.headers.get("X-Forwarded-Proto") or request.scheme)
    scheme = scheme.split(",")[0].strip() or "http"
    return f"{scheme}://{request.host}/join"


@qr_bp.route("/join/<code>")
def join_page(code: str):
    code = (code or "").upper()
    if not _CODE_RE.match(code):
        abort(404)
    return render_template("join.html", code=code,
                           app_url=f"auroraplay://join/{code}",
                           testflight_url=testflight_url())


@qr_bp.route("/native/qr/<code>")
def join_qr(code: str):
    code = (code or "").upper()
    if not _CODE_RE.match(code):
        abort(404)
    url = f"{join_url_base()}/{code}"
    try:
        import qrcode
    except ImportError:  # pragma: no cover - dependency missing
        abort(501)
    img = qrcode.make(url, box_size=10, border=2)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return Response(buf.getvalue(), mimetype="image/png",
                    headers={"Cache-Control": "no-store"})
