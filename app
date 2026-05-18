from flask import Flask, render_template, g, redirect, url_for, flash, request, jsonify, abort
import secrets
import sqlite3

app = Flask(__name__)
app.config['SECRET_KEY'] = secrets.token_urlsafe(16)
DATABASE = "library.db"

# Tabela zmieniona na "books", kolumna "done" zmieniona na "is_read"
SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS books(
id INTEGER PRIMARY KEY AUTOINCREMENT,
title TEXT NOT NULL,
is_read INTEGER NOT NULL DEFAULT 0 CHECK (is_read IN (0, 1)),
created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_books_read ON books(is_read);
CREATE INDEX IF NOT EXISTS idx_books_created_at ON books(created_at);
"""

def get_db():
    if "db" not in g:
        conn = sqlite3.connect(DATABASE)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON;")
        g.db = conn
    return g.db

@app.teardown_appcontext
def close_db(exception):
    db = g.pop("db", None)
    if db is not None:
        db.close()

def init_db():
    db = get_db()
    db.executescript(SCHEMA_SQL)
    db.commit()

@app.cli.command("init-db")
def init_db_command():
    init_db()
    print("✔ Zainicjowano bazę danych biblioteczki")

@app.cli.command("seed-db")
def seed_db_command():
    db = get_db()
    howManyBooks = db.execute("SELECT COUNT(*) FROM books").fetchone()[0]
    if howManyBooks == 0:
        db.executemany("INSERT INTO books(title, is_read) VALUES (?, ?)",
                       [["Władca Pierścieni", 1], ["Diuna", 0], ["Zrozumieć programowanie", 0]])
        db.commit()
        print("✔ Przykładowe książki zostały dodane.")
    else:
        print("❌ Baza już zawiera książki, seedowanie przerwane.")

# --- WIDOKI HTML ---

@app.route("/")
def index():
    return render_template("index.html")

@app.route("/ping-db")
def ping_db():
    db = get_db()
    db.execute("SELECT 1").fetchone()
    return render_template("ping.html")

@app.route("/list_books")
def list_books():
    db = get_db()
    books = db.execute("SELECT id, title, is_read, created_at FROM books ORDER BY created_at DESC").fetchall()
    return render_template("list_books.html", books=books)

@app.route("/book/<int:book_id>")
def book(book_id):
    db = get_db()
    book = db.execute("SELECT id, title, is_read, created_at FROM books WHERE id = ?", [book_id]).fetchone()
    if book is None:
        abort(404)
    return render_template("book.html", book=book)

@app.route("/add_book", methods=["GET", "POST"])
def add_book():
    if request.method == "POST":
        title = request.form.get("title")
        if len(title) < 3:
            flash("Tytuł książki musi mieć przynajmniej 3 znaki.")
            return render_template("add_book.html", title=title)
        
        db = get_db()
        existing_book = db.execute("SELECT id FROM books WHERE is_read = 0 AND title LIKE ?", [title]).fetchone()
        if existing_book:
            flash("Masz już tę książkę na liście 'do przeczytania'.")
            return render_template("add_book.html", title=title)

        db.execute("INSERT INTO books(title, is_read) VALUES (?, ?)", [title, 0])
        db.commit()
        flash("Książka została dodana do biblioteczki.")
        return redirect(url_for("list_books"))
    return render_template("add_book.html")

@app.route("/books/<int:book_id>/status", methods=["POST"])
def update_book_status(book_id):
    db = get_db()
    db.execute("UPDATE books SET is_read = NOT is_read WHERE id = ?", [book_id])
    db.commit()
    view_name = request.form.get("view_name")
    flash("Zaktualizowano status czytania.")
    if view_name == "book":
        return redirect(url_for("book", book_id=book_id))
    return redirect(url_for("list_books"))

@app.route("/books/<int:book_id>/delete", methods=["POST"])
def delete_book(book_id):
    db = get_db()
    db.execute("DELETE FROM books WHERE id = ?", [book_id])
    db.commit()
    flash("Usunięto książkę z listy.")
    return redirect(url_for("list_books"))

# --- API ---

@app.route("/api/books", methods=["GET"])
def api_books_list():
    db = get_db()
    rows = db.execute("SELECT id, title, is_read, created_at FROM books ORDER BY created_at DESC").fetchall()
    return jsonify([dict(row) for row in rows])

@app.route("/api/books", methods=["POST"])
def api_books_add():
    data = request.get_json(silent=True)
    if not data or "title" not in data:
        abort(400, description="Brak formatu JSON lub brakującego tytułu")

    title = data["title"].strip()
    if len(title) < 3:
        abort(400, description="Tytuł musi mieć co najmniej 3 znaki.")
        
    db = get_db()
    is_read = 1 if data.get("is_read") else 0
    cur = db.execute("INSERT INTO books(title, is_read) VALUES (?, ?)", [title, is_read])
    db.commit()

    book_id = cur.lastrowid
    row = db.execute("SELECT id, title, is_read, created_at FROM books WHERE id = ?", [book_id]).fetchone()
    return jsonify(dict(row)), 201

@app.route("/api/books/<int:book_id>", methods=["DELETE"])
def api_books_delete(book_id):
    db = get_db()
    cur = db.execute("DELETE FROM books WHERE id = ?", [book_id])
    db.commit()

    if cur.rowcount == 0:
        abort(404, description="Nie znaleziono książki")

    return "", 204

if __name__ == "__main__":
    app.run(debug=True)
