"""
Extrait les indices (nombre + lettre) des captures du morpion exclarrogatif
en utilisant l'API Claude avec vision.

Usage:
    python Extract-Indices.py <input_dir> <output_csv>

    Exemple:
    python Extract-Indices.py frames_crop_dedup indices.csv

Prérequis:
    - pip install anthropic
    - Variable d'environnement ANTHROPIC_API_KEY définie

Le fichier CSV de sortie contient : video_id, filename, number, letter
Trié par numéro pour reconstituer le message.
"""

import anthropic
import base64
import csv
import os
import sys
import time

def extract_index_from_image(client, image_path):
    """Envoie une image à Claude et extrait le nombre et la lettre."""
    with open(image_path, "rb") as f:
        image_data = base64.standard_b64encode(f.read()).decode("utf-8")

    ext = os.path.splitext(image_path)[1].lower()
    media_type = "image/jpeg" if ext in (".jpg", ".jpeg") else "image/png"

    response = client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=50,
        messages=[
            {
                "role": "user",
                "content": [
                    {
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": media_type,
                            "data": image_data,
                        },
                    },
                    {
                        "type": "text",
                        "text": (
                            "This image shows a whiteboard with magnetic letters. "
                            "There is a number and a single letter. "
                            "Reply ONLY with the number and the letter separated by a space. "
                            "Example: 42 E\n"
                            "If you cannot read them, reply: ? ?"
                        ),
                    },
                ],
            }
        ],
    )

    return response.content[0].text.strip()


def main():
    if len(sys.argv) < 3:
        print(f"Usage: python {sys.argv[0]} <input_dir> <output_csv>")
        sys.exit(1)

    input_dir = sys.argv[1]
    output_csv = sys.argv[2]

    if not os.path.isdir(input_dir):
        print(f"Erreur: le répertoire '{input_dir}' n'existe pas.")
        sys.exit(1)

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("Erreur: la variable d'environnement ANTHROPIC_API_KEY n'est pas définie.")
        print("Définissez-la avec: $env:ANTHROPIC_API_KEY = 'sk-ant-...'")
        sys.exit(1)

    client = anthropic.Anthropic(api_key=api_key)

    # Lister les images
    images = sorted([
        f for f in os.listdir(input_dir)
        if f.lower().endswith((".jpg", ".jpeg", ".png"))
    ])

    if not images:
        print(f"Aucune image trouvée dans '{input_dir}'.")
        sys.exit(1)

    print(f"Extraction des indices de {len(images)} image(s)...")
    print(f"Modèle: claude-haiku-4-5-20251001")
    print()

    results = []
    errors = 0

    for i, filename in enumerate(images):
        filepath = os.path.join(input_dir, filename)
        video_id = filename.rsplit("_", 1)[0] if "_" in filename else os.path.splitext(filename)[0]

        print(f"[{i + 1}/{len(images)}] {filename}", end=" -> ", flush=True)

        try:
            answer = extract_index_from_image(client, filepath)
            parts = answer.split()
            if len(parts) >= 2:
                number = parts[0]
                letter = parts[1]
                print(f"{number} {letter}")
                results.append({
                    "video_id": video_id,
                    "filename": filename,
                    "number": number,
                    "letter": letter,
                    "raw": answer,
                })
            else:
                print(f"réponse inattendue: {answer}")
                results.append({
                    "video_id": video_id,
                    "filename": filename,
                    "number": "?",
                    "letter": "?",
                    "raw": answer,
                })
                errors += 1
        except Exception as e:
            print(f"ERREUR: {e}")
            results.append({
                "video_id": video_id,
                "filename": filename,
                "number": "?",
                "letter": "?",
                "raw": str(e),
            })
            errors += 1

        # Petit délai pour ne pas dépasser les rate limits
        if i < len(images) - 1:
            time.sleep(0.2)

    # Trier par numéro
    def sort_key(r):
        try:
            return int(r["number"])
        except ValueError:
            return 99999

    results.sort(key=sort_key)

    # Écrire le CSV
    with open(output_csv, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["video_id", "filename", "number", "letter", "raw"])
        writer.writeheader()
        writer.writerows(results)

    print()
    print(f"--- RÉSULTATS ---")
    print(f"Extractions réussies: {len(results) - errors}")
    if errors > 0:
        print(f"Erreurs: {errors}")
    print(f"Fichier CSV: {output_csv}")

    # Afficher le message reconstitué
    print()
    print("--- MESSAGE RECONSTITUÉ ---")
    message_parts = [(r["number"], r["letter"]) for r in results if r["number"] != "?"]
    message = "".join(letter for _, letter in message_parts)
    print(message)
    print()
    print("Détail (numéro -> lettre):")
    for num, letter in message_parts:
        print(f"  {num}: {letter}")


if __name__ == "__main__":
    main()
