from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse, Response
from fastapi.staticfiles import StaticFiles

ROOT = Path(__file__).resolve().parent
DATA_ROOT = Path(os.environ.get("STORAGE_DIR", str(ROOT))).resolve()
MODEL_DIR = DATA_ROOT / "STL"
STATE_PATH = DATA_ROOT / "web_state.json"
VIEWER_PATH = ROOT / "STL-viewer.html"
VENDOR_DIR = ROOT / "vendor"

ID_RE = re.compile(r"^(?P<id>[0-9a-f]{32})__(?P<name>.+)$", re.IGNORECASE)

app = FastAPI(title="STL Viewer Web App")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)
if VENDOR_DIR.exists():
    app.mount("/vendor", StaticFiles(directory=VENDOR_DIR), name="vendor")


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def ensure_storage() -> None:
    DATA_ROOT.mkdir(parents=True, exist_ok=True)
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    if not STATE_PATH.exists():
        write_state(
            {
                "selected_model_id": None,
                "updated_at": utc_now(),
                "transforms": {},
                "hash_index": {},
                "model_hashes": {},
            }
        )


def load_state() -> dict[str, Any]:
    ensure_storage()
    try:
        state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
    except Exception:
        state = {
            "selected_model_id": None,
            "updated_at": utc_now(),
            "transforms": {},
            "hash_index": {},
            "model_hashes": {},
        }

    state.setdefault("selected_model_id", None)
    state.setdefault("updated_at", utc_now())
    state.setdefault("transforms", {})
    state.setdefault("hash_index", {})
    state.setdefault("model_hashes", {})

    if any(MODEL_DIR.glob("*.stl")) and (
        not state["hash_index"] or not state["model_hashes"]
    ):
        hash_index, model_hashes = rebuild_hash_index()
        state["hash_index"] = hash_index
        state["model_hashes"] = model_hashes
        write_state(state)
    return state


def write_state(state: dict[str, Any]) -> None:
    STATE_PATH.write_text(
        json.dumps(state, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def json_response(payload: Any, status_code: int = 200) -> Response:
    return Response(
        content=json.dumps(payload, ensure_ascii=False),
        status_code=status_code,
        media_type="application/json; charset=utf-8",
    )


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def rebuild_hash_index() -> tuple[dict[str, str], dict[str, str]]:
    hash_index: dict[str, str] = {}
    model_hashes: dict[str, str] = {}
    for path in MODEL_DIR.glob("*.stl"):
        model_id = model_id_for_path(path)
        digest = file_sha256(path)
        hash_index[digest] = model_id
        model_hashes[model_id] = digest
    return hash_index, model_hashes


def sanitize_filename(name: str) -> str:
    name = Path(name).name
    name = re.sub(r'[\\/:*?"<>|]+', "_", name).strip()
    return name or "model.stl"


def model_id_for_path(path: Path) -> str:
    match = ID_RE.match(path.stem)
    if match:
        return match.group("id")
    return hashlib.sha1(path.name.encode("utf-8")).hexdigest()[:16]


def display_name_for_path(path: Path) -> str:
    match = ID_RE.match(path.stem)
    if match:
        return f"{match.group('name')}.stl"
    return path.name


def file_path_for_id(model_id: str) -> Path | None:
    for path in MODEL_DIR.glob("*.stl"):
        if model_id_for_path(path) == model_id:
            return path
    return None


def model_record(path: Path) -> dict[str, Any]:
    stat = path.stat()
    model_id = model_id_for_path(path)
    name = display_name_for_path(path)
    state = load_state()
    return {
        "id": model_id,
        "name": name,
        "size": stat.st_size,
        "updated_at": datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc).isoformat(),
        "file_url": f"/api/models/{model_id}/file",
        "transform": state.get("transforms", {}).get(model_id, {"position": [0, 0, 0], "rotation": [0, 0, 0]}),
    }


def list_models() -> list[dict[str, Any]]:
    ensure_storage()
    models = [model_record(path) for path in MODEL_DIR.glob("*.stl")]
    models.sort(key=lambda item: item["updated_at"], reverse=True)
    return models


def upsert_uploaded_file(upload: UploadFile) -> dict[str, Any]:
    ensure_storage()
    original_name = sanitize_filename(upload.filename or "model.stl")
    data = upload.file.read()
    digest = hashlib.sha256(data).hexdigest()

    state = load_state()
    existing_id = state.get("hash_index", {}).get(digest)
    if existing_id:
        existing_path = file_path_for_id(existing_id)
        if existing_path is not None and existing_path.exists():
            return {
                "skipped": True,
                "reason": "duplicate",
                "source_name": original_name,
                "id": existing_id,
                "name": display_name_for_path(existing_path),
                "hash": digest,
            }

    model_id = uuid.uuid4().hex
    stored_name = f"{model_id}__{original_name}"
    dest = MODEL_DIR / stored_name
    dest.write_bytes(data)
    state.setdefault("hash_index", {})[digest] = model_id
    state.setdefault("model_hashes", {})[model_id] = digest
    state["updated_at"] = utc_now()
    write_state(state)

    record = model_record(dest)
    record["hash"] = digest
    record["skipped"] = False
    return record


def delete_model(model_id: str) -> bool:
    path = file_path_for_id(model_id)
    if path is None:
        return False
    state = load_state()
    digest = state.get("model_hashes", {}).pop(model_id, None)
    if digest is not None:
        state.get("hash_index", {}).pop(digest, None)
    path.unlink(missing_ok=True)
    state["updated_at"] = utc_now()
    write_state(state)
    return True


@app.get("/", response_class=HTMLResponse)
def root() -> FileResponse:
    return FileResponse(VIEWER_PATH)


@app.get("/api/models")
def api_list_models() -> Response:
    return json_response(list_models())


@app.get("/api/models/{model_id}")
def api_get_model(model_id: str) -> Response:
    path = file_path_for_id(model_id)
    if path is None:
        raise HTTPException(status_code=404, detail="Model not found")
    return json_response(model_record(path))


@app.get("/api/models/{model_id}/file")
def api_get_model_file(model_id: str) -> FileResponse:
    path = file_path_for_id(model_id)
    if path is None:
        raise HTTPException(status_code=404, detail="Model not found")
    return FileResponse(path, media_type="application/sla", filename=display_name_for_path(path))


@app.post("/api/models")
async def api_upload_models(files: list[UploadFile] = File(...)) -> Response:
    if not files:
        raise HTTPException(status_code=400, detail="No files provided")
    created = []
    skipped = []
    for upload in files:
        if not (upload.filename or "").lower().endswith(".stl"):
            continue
        result = upsert_uploaded_file(upload)
        if result.get("skipped"):
            skipped.append(result)
        else:
            created.append(result)
    return json_response({"created": created, "skipped": skipped})


@app.delete("/api/models/{model_id}")
def api_delete_model(model_id: str) -> Response:
    if not delete_model(model_id):
        raise HTTPException(status_code=404, detail="Model not found")
    state = load_state()
    if state.get("selected_model_id") == model_id:
        state["selected_model_id"] = None
    state.get("transforms", {}).pop(model_id, None)
    state["updated_at"] = utc_now()
    write_state(state)
    return json_response({"deleted": model_id})


@app.delete("/api/models")
def api_delete_all_models() -> Response:
    deleted = []
    for path in MODEL_DIR.glob("*.stl"):
        deleted.append(path.name)
        path.unlink(missing_ok=True)
    state = load_state()
    state["selected_model_id"] = None
    state["updated_at"] = utc_now()
    state["transforms"] = {}
    state["hash_index"] = {}
    state["model_hashes"] = {}
    write_state(state)
    return json_response({"deleted": deleted})


@app.get("/api/state")
def api_get_state() -> Response:
    state = load_state()
    state.setdefault("selected_model_id", None)
    state.setdefault("updated_at", utc_now())
    return json_response(state)


@app.put("/api/state")
async def api_put_state(payload: dict[str, Any]) -> Response:
    selected_model_id = payload.get("selected_model_id")
    if selected_model_id is not None:
        if selected_model_id == "":
            selected_model_id = None
        elif file_path_for_id(str(selected_model_id)) is None:
            raise HTTPException(status_code=404, detail="Selected model not found")

    base_state = load_state()
    state = {
        "selected_model_id": selected_model_id,
        "updated_at": utc_now(),
        "transforms": base_state.get("transforms", {}),
        "hash_index": base_state.get("hash_index", {}),
        "model_hashes": base_state.get("model_hashes", {}),
    }
    write_state(state)
    return json_response(state)


@app.get("/api/models/{model_id}/transform")
def api_get_model_transform(model_id: str) -> Response:
    path = file_path_for_id(model_id)
    if path is None:
        raise HTTPException(status_code=404, detail="Model not found")
    state = load_state()
    transform = state.get("transforms", {}).get(
        model_id,
        {"position": [0, 0, 0], "rotation": [0, 0, 0]},
    )
    return json_response(transform)


@app.put("/api/models/{model_id}/transform")
async def api_put_model_transform(model_id: str, payload: dict[str, Any]) -> Response:
    path = file_path_for_id(model_id)
    if path is None:
        raise HTTPException(status_code=404, detail="Model not found")

    position = payload.get("position", [0, 0, 0])
    rotation = payload.get("rotation", [0, 0, 0])
    if len(position) != 3 or len(rotation) != 3:
        raise HTTPException(status_code=400, detail="Transform must contain 3D position and rotation")

    state = load_state()
    state["transforms"][model_id] = {
        "position": [float(v) for v in position],
        "rotation": [float(v) for v in rotation],
    }
    state["updated_at"] = utc_now()
    write_state(state)
    return json_response(state["transforms"][model_id])


def main() -> None:
    parser = argparse.ArgumentParser(description="STL Viewer web app server")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8000)
    args = parser.parse_args()

    import uvicorn

    uvicorn.run("server_app:app", host=args.host, port=args.port, reload=False, log_level="info")


if __name__ == "__main__":
    main()
