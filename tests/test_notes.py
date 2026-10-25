import os

os.environ["DATABASE_URL"] = "sqlite://"

from fastapi.testclient import TestClient

from app.database import Base, engine
from app.main import app


def client_with_empty_database():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    return TestClient(app)


def test_health_endpoint():
    with client_with_empty_database() as client:
        assert client.get("/health").json() == {"status": "healthy"}


def test_create_list_and_delete_note():
    with client_with_empty_database() as client:
        created = client.post("/notes", json={"content": "First note"})
        assert created.status_code == 201
        note_id = created.json()["id"]

        notes = client.get("/notes")
        assert notes.status_code == 200
        assert [note["content"] for note in notes.json()] == ["First note"]

        deleted = client.delete(f"/notes/{note_id}")
        assert deleted.status_code == 204
        assert client.get("/notes").json() == []


def test_note_validation_and_missing_note():
    with client_with_empty_database() as client:
        assert client.post("/notes", json={"content": ""}).status_code == 422
        assert client.post("/notes", json={"content": "x" * 501}).status_code == 422
        assert client.delete("/notes/999").status_code == 404

