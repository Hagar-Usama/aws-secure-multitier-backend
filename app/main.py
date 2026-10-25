from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException, Response, status
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session

from . import crud, schemas
from .database import create_tables, get_db


@asynccontextmanager
async def application_lifespan(_: FastAPI):
    create_tables()
    yield


app = FastAPI(title="Notes API", lifespan=application_lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://127.0.0.1:8080", "http://localhost:8080"],
    allow_methods=["GET", "POST", "DELETE"],
    allow_headers=["Content-Type"],
)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "healthy"}


@app.get("/notes", response_model=list[schemas.NoteRead])
def get_notes(session: Session = Depends(get_db)) -> list[schemas.NoteRead]:
    return crud.list_notes(session)


@app.post("/notes", response_model=schemas.NoteRead, status_code=status.HTTP_201_CREATED)
def post_note(note: schemas.NoteCreate, session: Session = Depends(get_db)) -> schemas.NoteRead:
    return crud.create_note(session, note.content)


@app.delete("/notes/{note_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_note(note_id: int, session: Session = Depends(get_db)) -> Response:
    if not crud.delete_note(session, note_id):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Note not found")
    return Response(status_code=status.HTTP_204_NO_CONTENT)

