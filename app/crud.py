from sqlalchemy import select
from sqlalchemy.orm import Session

from .models import Note


def list_notes(session: Session) -> list[Note]:
    statement = select(Note).order_by(Note.created_at.desc(), Note.id.desc())
    return list(session.scalars(statement))


def create_note(session: Session, content: str) -> Note:
    note = Note(content=content)
    session.add(note)
    session.commit()
    session.refresh(note)
    return note


def delete_note(session: Session, note_id: int) -> bool:
    note = session.get(Note, note_id)
    if note is None:
        return False
    session.delete(note)
    session.commit()
    return True

